module u_rec #(parameter WIDTH=8) (
    input clk, rst,
    input in,
    output ready,
    output reg busy,
    output reg [WIDTH-1:0] out
);      
    reg [3:0] count;
    reg sync0, sync1;

    reg [$clog2(WIDTH):0] nbits;
  
    assign ready = ~busy;

    always @(posedge clk or negedge rst) begin
        if(!rst) begin
            sync0 <= 1;
            sync1 <= 1;
        end else begin
            sync0 <= in;
            sync1 <= sync0;
        end
    end

    always @(posedge clk or negedge rst) begin
        if(!rst) begin
            count <= 0;
        end else if(busy) begin
            count <= count+1;
        end else begin
            count <= 0;
        end
    end
    
    always @(posedge clk or negedge rst) begin
        if(!rst) begin
            out <= 0;
            nbits <= 0;
            busy <= 0;
        end else begin
            if(count==7) begin
                if(nbits==0) begin
                    if(sync1==0)
                        nbits <= nbits+1;
                    else
                        busy <= 0;
                end else if(nbits<=WIDTH) begin
                    out <= ({sync1, out} >> 1);
                    nbits <= nbits+1;
                end else begin
                    nbits <= 0;
                    busy <= 0;
                end
            end else if(sync1==0) begin
                busy <= 1;
            end
        end
    end
endmodule
