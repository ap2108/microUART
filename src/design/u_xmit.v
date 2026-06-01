module u_xmit #(parameter WIDTH=8) (
    input clk, rst,
    input [WIDTH-1:0] in,
    input en,
    output reg done, active,
    output out
);      
    reg [3:0] count;
    reg [WIDTH+1:0] tx_r;

    always @(posedge clk or negedge rst) begin
        if(!rst)
            count <= 0;
        else if(active) begin
            count <= count+1;
        end else begin
            count <= 0;
        end
    end

    assign out = active ? tx_r[0] : 1;

    always @(posedge clk or negedge rst) begin
        if(!rst) begin
            active <= 0;
            tx_r <= {1'b1, in, 1'b0};
            done <= 1;
        end else begin
            if(active) begin
                done <= 0;
                if(count==15) begin
                    tx_r <= tx_r >> 1;
                    if(tx_r==1) begin
                        done <= 1;
                        if(en==0)
                            active <= 0;
                        else 
                            tx_r <= {1'b1, in, 1'b0};
                    end
                end  
            end else if(en==1) begin
                tx_r <= {1'b1, in, 1'b0};
                active <= 1;
                done <= 0;
            end
 
        end
    end
endmodule
