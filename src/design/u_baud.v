module u_baud #(parameter SYS_CLK_FREQ=50000000, BAUD_RATE=9600)(
    input clk_in, rst,
    output reg clk_out
);
    localparam integer MAX_COUNT = SYS_CLK_FREQ/(BAUD_RATE*32);
    reg [$clog2(MAX_COUNT)-1:0] count;

    always @(posedge clk_in or negedge rst) begin
        if(!rst) begin
            count <= 0;
            clk_out <= 0;
        end else if(count < MAX_COUNT) begin
            count <= count+1;
        end else begin
            count <= 0;
            clk_out <= ~clk_out;
        end
    end
endmodule
