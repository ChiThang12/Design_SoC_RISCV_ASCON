`timescale 1ns/1ps

module axi4_master_mux_2m #(
    parameter ID_WIDTH   = 4,
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH / 8
) (
    input  wire clk,
    input  wire rst_n,

    input  wire [ID_WIDTH-1:0]   m0_arid,
    input  wire [ADDR_WIDTH-1:0] m0_araddr,
    input  wire [7:0]            m0_arlen,
    input  wire [2:0]            m0_arsize,
    input  wire [1:0]            m0_arburst,
    input  wire [2:0]            m0_arprot,
    input  wire                  m0_arvalid,
    output wire                  m0_arready,
    output wire [ID_WIDTH-1:0]   m0_rid,
    output wire [DATA_WIDTH-1:0] m0_rdata,
    output wire [1:0]            m0_rresp,
    output wire                  m0_rlast,
    output wire                  m0_rvalid,
    input  wire                  m0_rready,
    input  wire [ID_WIDTH-1:0]   m0_awid,
    input  wire [ADDR_WIDTH-1:0] m0_awaddr,
    input  wire [7:0]            m0_awlen,
    input  wire [2:0]            m0_awsize,
    input  wire [1:0]            m0_awburst,
    input  wire [2:0]            m0_awprot,
    input  wire                  m0_awvalid,
    output wire                  m0_awready,
    input  wire [DATA_WIDTH-1:0] m0_wdata,
    input  wire [STRB_WIDTH-1:0] m0_wstrb,
    input  wire                  m0_wlast,
    input  wire                  m0_wvalid,
    output wire                  m0_wready,
    output wire [ID_WIDTH-1:0]   m0_bid,
    output wire [1:0]            m0_bresp,
    output wire                  m0_bvalid,
    input  wire                  m0_bready,

    input  wire [ID_WIDTH-1:0]   m1_arid,
    input  wire [ADDR_WIDTH-1:0] m1_araddr,
    input  wire [7:0]            m1_arlen,
    input  wire [2:0]            m1_arsize,
    input  wire [1:0]            m1_arburst,
    input  wire [2:0]            m1_arprot,
    input  wire                  m1_arvalid,
    output wire                  m1_arready,
    output wire [ID_WIDTH-1:0]   m1_rid,
    output wire [DATA_WIDTH-1:0] m1_rdata,
    output wire [1:0]            m1_rresp,
    output wire                  m1_rlast,
    output wire                  m1_rvalid,
    input  wire                  m1_rready,
    input  wire [ID_WIDTH-1:0]   m1_awid,
    input  wire [ADDR_WIDTH-1:0] m1_awaddr,
    input  wire [7:0]            m1_awlen,
    input  wire [2:0]            m1_awsize,
    input  wire [1:0]            m1_awburst,
    input  wire [2:0]            m1_awprot,
    input  wire                  m1_awvalid,
    output wire                  m1_awready,
    input  wire [DATA_WIDTH-1:0] m1_wdata,
    input  wire [STRB_WIDTH-1:0] m1_wstrb,
    input  wire                  m1_wlast,
    input  wire                  m1_wvalid,
    output wire                  m1_wready,
    output wire [ID_WIDTH-1:0]   m1_bid,
    output wire [1:0]            m1_bresp,
    output wire                  m1_bvalid,
    input  wire                  m1_bready,

    output wire [ID_WIDTH-1:0]   s_arid,
    output wire [ADDR_WIDTH-1:0] s_araddr,
    output wire [7:0]            s_arlen,
    output wire [2:0]            s_arsize,
    output wire [1:0]            s_arburst,
    output wire [2:0]            s_arprot,
    output wire                  s_arvalid,
    input  wire                  s_arready,
    input  wire [ID_WIDTH-1:0]   s_rid,
    input  wire [DATA_WIDTH-1:0] s_rdata,
    input  wire [1:0]            s_rresp,
    input  wire                  s_rlast,
    input  wire                  s_rvalid,
    output wire                  s_rready,
    output wire [ID_WIDTH-1:0]   s_awid,
    output wire [ADDR_WIDTH-1:0] s_awaddr,
    output wire [7:0]            s_awlen,
    output wire [2:0]            s_awsize,
    output wire [1:0]            s_awburst,
    output wire [2:0]            s_awprot,
    output wire                  s_awvalid,
    input  wire                  s_awready,
    output wire [DATA_WIDTH-1:0] s_wdata,
    output wire [STRB_WIDTH-1:0] s_wstrb,
    output wire                  s_wlast,
    output wire                  s_wvalid,
    input  wire                  s_wready,
    input  wire [ID_WIDTH-1:0]   s_bid,
    input  wire [1:0]            s_bresp,
    input  wire                  s_bvalid,
    output wire                  s_bready
);

    reg read_active;
    reg read_owner;
    reg write_active;
    reg write_owner;

    wire pick_read_m0  = !read_active && m0_arvalid;
    wire pick_read_m1  = !read_active && !m0_arvalid && m1_arvalid;
    wire read_sel_m0   = read_active ? !read_owner : pick_read_m0;
    wire read_sel_m1   = read_active ?  read_owner : pick_read_m1;

    wire pick_write_m0 = !write_active && m0_awvalid;
    wire pick_write_m1 = !write_active && !m0_awvalid && m1_awvalid;
    wire write_sel_m0  = write_active ? !write_owner : pick_write_m0;
    wire write_sel_m1  = write_active ?  write_owner : pick_write_m1;

    assign s_arid    = read_sel_m0 ? m0_arid    : (read_sel_m1 ? m1_arid    : {ID_WIDTH{1'b0}});
    assign s_araddr  = read_sel_m0 ? m0_araddr  : (read_sel_m1 ? m1_araddr  : {ADDR_WIDTH{1'b0}});
    assign s_arlen   = read_sel_m0 ? m0_arlen   : (read_sel_m1 ? m1_arlen   : 8'h00);
    assign s_arsize  = read_sel_m0 ? m0_arsize  : (read_sel_m1 ? m1_arsize  : 3'b000);
    assign s_arburst = read_sel_m0 ? m0_arburst : (read_sel_m1 ? m1_arburst : 2'b00);
    assign s_arprot  = read_sel_m0 ? m0_arprot  : (read_sel_m1 ? m1_arprot  : 3'b000);
    assign s_arvalid = !read_active && (pick_read_m0 || pick_read_m1);

    assign m0_arready = pick_read_m0 && s_arready;
    assign m1_arready = pick_read_m1 && s_arready;

    assign m0_rid    = s_rid;
    assign m0_rdata  = s_rdata;
    assign m0_rresp  = s_rresp;
    assign m0_rlast  = s_rlast;
    assign m0_rvalid = read_active && !read_owner && s_rvalid;

    assign m1_rid    = s_rid;
    assign m1_rdata  = s_rdata;
    assign m1_rresp  = s_rresp;
    assign m1_rlast  = s_rlast;
    assign m1_rvalid = read_active && read_owner && s_rvalid;

    assign s_rready = read_active ? (read_owner ? m1_rready : m0_rready) : 1'b0;

    assign s_awid    = pick_write_m0 ? m0_awid    : (pick_write_m1 ? m1_awid    : {ID_WIDTH{1'b0}});
    assign s_awaddr  = pick_write_m0 ? m0_awaddr  : (pick_write_m1 ? m1_awaddr  : {ADDR_WIDTH{1'b0}});
    assign s_awlen   = pick_write_m0 ? m0_awlen   : (pick_write_m1 ? m1_awlen   : 8'h00);
    assign s_awsize  = pick_write_m0 ? m0_awsize  : (pick_write_m1 ? m1_awsize  : 3'b000);
    assign s_awburst = pick_write_m0 ? m0_awburst : (pick_write_m1 ? m1_awburst : 2'b00);
    assign s_awprot  = pick_write_m0 ? m0_awprot  : (pick_write_m1 ? m1_awprot  : 3'b000);
    assign s_awvalid = !write_active && (pick_write_m0 || pick_write_m1);

    assign m0_awready = pick_write_m0 && s_awready;
    assign m1_awready = pick_write_m1 && s_awready;

    assign s_wdata  = write_sel_m0 ? m0_wdata  : (write_sel_m1 ? m1_wdata  : {DATA_WIDTH{1'b0}});
    assign s_wstrb  = write_sel_m0 ? m0_wstrb  : (write_sel_m1 ? m1_wstrb  : {STRB_WIDTH{1'b0}});
    assign s_wlast  = write_sel_m0 ? m0_wlast  : (write_sel_m1 ? m1_wlast  : 1'b0);
    assign s_wvalid = write_active && ((write_owner ? m1_wvalid : m0_wvalid));

    assign m0_wready = write_active && !write_owner && s_wready;
    assign m1_wready = write_active &&  write_owner && s_wready;

    assign m0_bid    = s_bid;
    assign m0_bresp  = s_bresp;
    assign m0_bvalid = write_active && !write_owner && s_bvalid;

    assign m1_bid    = s_bid;
    assign m1_bresp  = s_bresp;
    assign m1_bvalid = write_active && write_owner && s_bvalid;

    assign s_bready = write_active ? (write_owner ? m1_bready : m0_bready) : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_active  <= 1'b0;
            read_owner   <= 1'b0;
            write_active <= 1'b0;
            write_owner  <= 1'b0;
        end else begin
            if (!read_active) begin
                if (s_arvalid && s_arready) begin
                    read_active <= 1'b1;
                    read_owner  <= pick_read_m1;
                end
            end else if (s_rvalid && s_rready && s_rlast) begin
                read_active <= 1'b0;
            end

            if (!write_active) begin
                if (s_awvalid && s_awready) begin
                    write_active <= 1'b1;
                    write_owner  <= pick_write_m1;
                end
            end else if (s_bvalid && s_bready) begin
                write_active <= 1'b0;
            end
        end
    end

endmodule
