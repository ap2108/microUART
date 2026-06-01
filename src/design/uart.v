module uart #(
    parameter WIDTH=8, SYS_CLK_FREQ=50000000, BAUD_RATE=2400
) (
    input sys_clk, sys_rst_l,
    input xmitH, uart_REC_dataH,
    input [WIDTH-1:0] xmit_dataH,
    output xmit_doneH, uart_XMIT_dataH, rec_readyH, xmit_active, rec_busy,
    output [WIDTH-1:0] rec_dataH
);  
    wire uart_clk;

    u_baud #(
        .SYS_CLK_FREQ(SYS_CLK_FREQ), 
        .BAUD_RATE(BAUD_RATE)
    ) u1(
        .clk_in(sys_clk),
        .rst(sys_rst_l),
        .clk_out(uart_clk)
    );

    u_xmit #(
        .WIDTH(WIDTH)
    ) u2(
        .clk(uart_clk),
        .rst(sys_rst_l),
        .in(xmit_dataH),
        .en(xmitH),
        .done(xmit_doneH),
        .active(xmit_active),
        .out(uart_XMIT_dataH)
    );   
    
    u_rec #(
         .WIDTH(WIDTH)
    ) u3(
        .clk(uart_clk),
        .rst(sys_rst_l),
        .in(uart_REC_dataH),
        .ready(rec_readyH),
        .busy(rec_busy),
        .out(rec_dataH)
    );  
endmodule