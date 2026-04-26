// gba_analogizer_video.sv
//
// Analogizer-only CRT raster generator for the GBA core.
//
// The duplicate framebuffer this originally used would exceed the device's
// M10K BRAM budget. Instead, this module shares video_adapter's existing
// framebuffer read port via time-division: video_adapter reads on vid_ce=1
// cycles, this module reads on vid_ce=0 cycles. No extra M10K required.
//
// Framebuffer constraint: the BRAM delivers one pixel per 2 clk_vid cycles
// (vid_ce cadence). Both modes MUST use src_x = h_pos[9:1] (2 output clocks
// per source pixel). One-clock-per-pixel ("true 1x") is not achievable.
//
// Timing target (clk_vid = 8.388608 MHz, H_TOTAL=560, V_TOTAL=262):
//   H_rate = 8.388608 / 560 = 14.98 kHz
//   V_rate = 14.98 kHz / 262 = 57.2 Hz
//
// scale_mode input (from interact.json 0x8C, synced to clk_vid in core_top):
//   0 = Exact 1x  — Shows centre 120 GBA pixels (60..179) in a 240-clock
//                   window centred in H_ACTIVE. Fits inside the TV safe area;
//                   no pixel cutoff. Image is smaller with black borders.
//   1 = Wide 2x   — H_ACTIVE (480) pixels wide, all 240 GBA pixels visible.
//                   TV overscan may crop a few edge pixels depending on the TV.

`default_nettype none

module gba_analogizer_video #(
    parameter bit SYNC_ACTIVE_LOW = 1'b0,

    parameter int SRC_W = 240,
    parameter int SRC_H = 160,

    parameter int H_TOTAL  = 536,
    parameter int H_ACTIVE = 448,
    parameter int H_FP     = 16,
    parameter int H_SYNC   = 40,
    parameter int H_BP     = H_TOTAL - H_ACTIVE - H_FP - H_SYNC,

    parameter int V_TOTAL  = 262,
    parameter int V_ACTIVE = 160,
    parameter int V_TOP    = 51,
    parameter int V_FP     = 4,
    parameter int V_SYNC   = 3,

    parameter bit TEST_PATTERN = 1'b0
) (
    input  wire        clk_vid,
    input  wire        reset,
    input  wire [1:0]  scale_mode,   // 0=Exact 1x, 1=Wide 2x

    // Shared framebuffer read port (from video_adapter, time-multiplexed)
    // video_adapter samples fb_rd_addr on vid_ce=0 cycles and returns data
    // in fb_rd_data on the next vid_ce=1 cycle (fb_rd_valid=1).
    output wire [15:0] fb_rd_addr,
    input  wire [17:0] fb_rd_data,
    input  wire        fb_rd_valid,   // = vid_ce from video_adapter

    // CRT video outputs (clk_vid domain)
    output reg  [23:0] rgb,
    output reg         hblank,
    output reg         vblank,
    output reg         blankn,
    output reg         hsync,
    output reg         vsync,
    output reg         csync,

    output wire        video_clk,
    output wire        ce_pix
);

    // ---- Scale mode decode ----
    wire mode_2x = (scale_mode == 2'd1);

    // Active pixel window: both modes use 2 output clocks per source pixel.
    //   1x: 240-clock window centred in H_ACTIVE; shows GBA pixels 60..179.
    //   2x: 480-clock window left-aligned; shows all 240 GBA pixels.
    localparam [9:0] LP_H_ACTIVE   = H_ACTIVE[9:0];         // 480
    localparam [9:0] LP_H_LEFT_1X  = (H_ACTIVE - 240) / 2; // 120
    localparam [8:0] LP_SRC_OFS_1X = 9'd60;                 // skip first 60 GBA columns

    wire [9:0] h_active_dyn = mode_2x ? LP_H_ACTIVE  : 10'd240;
    wire [9:0] h_left       = mode_2x ? 10'd0         : LP_H_LEFT_1X;

    // ---- Raster counters ----
    reg [9:0] h_count;
    reg [8:0] v_count;

    wire end_of_line  = (h_count == H_TOTAL - 1);
    wire end_of_frame = (v_count == V_TOTAL - 1);

    always @(posedge clk_vid) begin
        if (reset) begin
            h_count <= '0;
            v_count <= '0;
        end else begin
            if (end_of_line) begin
                h_count <= '0;
                v_count <= end_of_frame ? '0 : v_count + 1'b1;
            end else begin
                h_count <= h_count + 1'b1;
            end
        end
    end

    // ---- Active / sync regions ----
    // h_active: full H_ACTIVE band — governs hblank signal
    wire h_active = (h_count < H_ACTIVE);
    wire v_active = (v_count >= V_TOP) && (v_count < V_TOP + V_ACTIVE);

    // active_h: centering window within h_active — governs pixel output
    wire active_h = (h_count >= h_left) && (h_count < h_left + h_active_dyn);
    wire active   = active_h && v_active;

    wire hsync_region =
        (h_count >= H_ACTIVE + H_FP) &&
        (h_count <  H_ACTIVE + H_FP + H_SYNC);

    wire vsync_region =
        (v_count >= V_TOP + V_ACTIVE + V_FP) &&
        (v_count <  V_TOP + V_ACTIVE + V_FP + V_SYNC);

    // ---- Source pixel mapping ----
    wire [9:0] h_pos = h_count - h_left;

    // Both modes: 2 output clocks per source pixel (FB constraint).
    // 1x centre-crop: offset by 60 to display GBA columns 60..179.
    // 2x full-width:  offset 0, displays GBA columns 0..239.
    wire [8:0] src_x = h_pos[9:1] + (mode_2x ? 9'd0 : LP_SRC_OFS_1X);
    wire [8:0] src_y = v_count - V_TOP;

    // src_y * 240 via shift-subtract (256 - 16 = 240)
    wire [16:0] src_y_times_240 =
        ({8'd0, src_y} << 8) - ({8'd0, src_y} << 4);
    wire [16:0] read_addr_calc = src_y_times_240 + src_x;

    // ---- Shared framebuffer read (via video_adapter time-multiplexed port) ----
    // Clamp to address 0 outside the active centering window so we never
    // request an out-of-range address when the result would be discarded anyway.
    wire src_in_range = active_h && v_active && (src_x < SRC_W) && (src_y < SRC_H);
    assign fb_rd_addr = src_in_range ? read_addr_calc[15:0] : 16'd0;

    // Latch pixel whenever video_adapter delivers new data (vid_ce=1).
    reg [17:0] pixel_read;
    always @(posedge clk_vid) begin
        if (reset)
            pixel_read <= '0;
        else if (fb_rd_valid)
            pixel_read <= fb_rd_data;
    end

    // 6-bit per channel → 8-bit (replicate top 2 bits into bottom 2)
    wire [7:0] r8 = {pixel_read[17:12], pixel_read[17:16]};
    wire [7:0] g8 = {pixel_read[11:6],  pixel_read[11:10]};
    wire [7:0] b8 = {pixel_read[5:0],   pixel_read[5:4]};

    // ---- Optional sync test pattern ----
    wire [23:0] test_rgb =
        (h_count < (H_ACTIVE / 4) * 1) ? 24'hFF0000 :
        (h_count < (H_ACTIVE / 4) * 2) ? 24'h00FF00 :
        (h_count < (H_ACTIVE / 4) * 3) ? 24'h0000FF :
                                          24'hFFFFFF;

    wire [23:0] source_rgb = TEST_PATTERN ? test_rgb : {r8, g8, b8};

    // ---- Output pipeline ----
    reg active_d;
    reg hsync_region_d;
    reg vsync_region_d;

    always @(posedge clk_vid) begin
        if (reset) begin
            active_d       <= 1'b0;
            hsync_region_d <= 1'b0;
            vsync_region_d <= 1'b0;
            rgb    <= 24'h000000;
            hblank <= 1'b1;
            vblank <= 1'b1;
            blankn <= 1'b0;
            hsync  <= SYNC_ACTIVE_LOW ? 1'b1 : 1'b0;
            vsync  <= SYNC_ACTIVE_LOW ? 1'b1 : 1'b0;
            csync  <= SYNC_ACTIVE_LOW ? 1'b1 : 1'b0;
        end else begin
            active_d       <= active;
            hsync_region_d <= hsync_region;
            vsync_region_d <= vsync_region;

            rgb    <= active_d ? source_rgb : 24'h000000;
            hblank <= ~h_active;
            vblank <= ~v_active;
            blankn <= active_d;

            if (SYNC_ACTIVE_LOW) begin
                hsync <= ~hsync_region_d;
                vsync <= ~vsync_region_d;
                csync <= ~(hsync_region_d ^ vsync_region_d);
            end else begin
                hsync <= hsync_region_d;
                vsync <= vsync_region_d;
                csync <=  hsync_region_d ^ vsync_region_d;
            end
        end
    end

    assign video_clk = clk_vid;
    assign ce_pix    = 1'b1;

endmodule

`default_nettype wire
