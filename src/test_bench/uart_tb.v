`timescale 1us/1ns

module uart_tb;


    localparam  real SYS_CLK_MHZ = 100;
    localparam  BAUD_RATE   = 9600;
    localparam  WIDTH       = 8;

    localparam real SYS_CLK_HALF_PERIOD = 1/(SYS_CLK_MHZ * 2);
    localparam  BAUD_CLKS  = (SYS_CLK_MHZ*1000) / BAUD_RATE;

    reg              sys_clk;
    reg              sys_rst_l;
    reg              xmitH;
    reg  [WIDTH-1:0] xmit_dataH;
    wire             xmit_doneH;
    wire             uart_XMIT_dataH;
    wire             xmit_active;
    reg              uart_REC_dataH;
    wire             rec_readyH;
    wire             rec_busy;
    wire [WIDTH-1:0] rec_dataH;

    uart #(
        .WIDTH        (WIDTH),
        .SYS_CLK_FREQ (SYS_CLK_MHZ*1_000_000),
        .BAUD_RATE    (BAUD_RATE)
    ) dut (
        .sys_clk         (sys_clk),
        .sys_rst_l       (sys_rst_l),
        .xmitH           (xmitH),
        .xmit_dataH      (xmit_dataH),
        .uart_REC_dataH  (uart_REC_dataH),
        .xmit_doneH      (xmit_doneH),
        .uart_XMIT_dataH (uart_XMIT_dataH),
        .rec_readyH      (rec_readyH),
        .rec_busy        (rec_busy),
        .xmit_active     (xmit_active),
        .rec_dataH       (rec_dataH)
    );
    assign uart_clk = dut.u1.clk_out;

    initial sys_clk = 0;
    always #(SYS_CLK_HALF_PERIOD) sys_clk = ~sys_clk;

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, uart_tb);
    end

    reg [WIDTH+1:0] exp_frame, got_frame;
    reg invalid_start;

    integer total_cases = 0;
    integer pass_count = 0;

    // Transmitter ---------------------------------------------------------------------------------------
    task check_tx(input integer tc);
        integer i;
        reg [WIDTH+1:0] exp_frame_prev;
        reg pass, flag_pass; 
        begin           
            exp_frame_prev = exp_frame;  
            @(posedge uart_clk);
            pass = 1; flag_pass =1; 
            total_cases = total_cases +1;

            for(i=0; i<=WIDTH+1; i=i+1) begin
                repeat(i==0 ? 15 : 16) begin
                    #0.01;
                    if(exp_frame_prev[i] != uart_XMIT_dataH) 
                        pass = 0; 
                    if((xmit_active!=1 || xmit_doneH!=0) && exp_frame[0]==0)
                        flag_pass = 0;
                    got_frame[i] = uart_XMIT_dataH;
                    
                    @(posedge uart_clk); 
                end
            end

            #0.01;
            if(xmitH && ~xmit_active) flag_pass=0;
            if(!xmit_doneH) flag_pass=0;
            
            if(pass && flag_pass) begin
                $write("TC=%d | PASS | EXP_FRAME: [START=%b  DATA=%b  STOP=%b] | GOT_FRAME: [START=%b  DATA=%b  STOP=%b] | ", tc,
                exp_frame_prev[0], exp_frame_prev[WIDTH:1], exp_frame_prev[WIDTH+1], got_frame[0], got_frame[WIDTH:1], got_frame[WIDTH+1]);
                pass_count = pass_count +1;
            end else begin
                $write("TC=%d | FAIL | EXP_FRAME: [START=%b  DATA=%b  STOP=%b] | GOT_FRAME: [START=%b  DATA=%b  STOP=%b] | ", tc,
                exp_frame_prev[0], exp_frame_prev[WIDTH:1], exp_frame_prev[WIDTH+1], got_frame[0], got_frame[WIDTH:1], got_frame[WIDTH+1]);
            end
            if(flag_pass)
                $display("FLAG CHECK PASS");
            else 
                $display("FLAG CHECK FAIL");
        end
    endtask

    task drive_tx(input [WIDTH-1:0] in, input in_xmitH);
        integer i;
        begin
            repeat(159) @(posedge uart_clk);
            @(negedge uart_clk);
            xmitH = in_xmitH;
            xmit_dataH = in;

            exp_frame = in_xmitH ? {1'b1, in, 1'b0} : {(WIDTH+2){1'b1}};
            @(posedge uart_clk);
        end
    endtask

    task check_and_drive_tx(input integer prev_tc, input [WIDTH-1:0] in, input in_xmitH);
        begin
            fork 
                drive_tx(in, in_xmitH);
                check_tx(prev_tc);
            join
        end
    endtask

    // Reciever ---------------------------------------------------------------------------------------
    task drive_and_check_rx(input [WIDTH-1:0] in, input integer tc);
        integer i;
        reg pass, flag_pass;
        begin
            pass = 1;
            flag_pass = 1;
            total_cases = total_cases+1;
            fork
                begin : DRIVE

                    // invalid start bit
                    if(invalid_start) begin
                        uart_REC_dataH = 0;
                        repeat(2) @(posedge uart_clk);
                        uart_REC_dataH = 1;
                        disable DRIVE;
                    end

                    // start bit
                    uart_REC_dataH = 0;
                    repeat(16) @(posedge uart_clk);

                    // data
                    for(i=0; i<WIDTH; i=i+1) begin
                        uart_REC_dataH = in[i];
                        repeat(16) @(posedge uart_clk);
                    end

                    // stop bit
                    uart_REC_dataH = 1;
                    repeat(16) @(posedge uart_clk);
                end

                begin : CHECK
                    repeat(2) @(posedge uart_clk);

                    if(invalid_start) begin
                        repeat(8) @(posedge uart_clk);    
                        #0.01;
                        disable CHECK;
                    end

                    repeat((16*9)+8) begin
                        #0.01;
                        @(posedge uart_clk);
                    end
                    
                end
            join

            if(!invalid_start) begin
                #0.01;
                if(rec_busy!=0 || rec_readyH!=1) flag_pass=0;
                if(rec_dataH != in) pass=0;
            end

            // display
            if(pass && flag_pass) begin
                $write("TC=%d | PASS | EXP_DATA=%b | GOT_DATA=%b | ", tc,
                in, rec_dataH);
                pass_count=pass_count+1;
            end else begin
                $write("TC=%d | FAIL | EXP_DATA=%b | GOT_DATA=%b | ", tc,
                in, rec_dataH);
            end

            if(flag_pass)
                $display("FLAG CHECK PASS");
            else 
                $display("FLAG CHECK FAIL");
        end
    endtask

    task do_reset;
        begin
            @(negedge sys_clk);
            sys_rst_l = 0;
            @(posedge sys_clk);
            sys_rst_l = 1;
            uart_REC_dataH = 1;
            invalid_start = 0;
            #0.01;
        end
    endtask

    // initial block ------------------------------------------------------------------------------------------------------
    initial begin
        do_reset();
        
        // feature1
        drive_tx(8'hB3, 1);
        check_tx(1);
        
        // feature2
        drive_tx(8'b1111_1111, 1);
        check_tx(2);

        // feature3
        drive_tx(8'b0000_0000, 1);
        check_tx(3);

        // feature4
        drive_tx(8'hC5, 1);
        check_and_drive_tx(4, 8'h7D, 1);
        check_and_drive_tx(4, 8'h4F, 1);
        check_tx(4);

        // feature5
        drive_tx(8'hA4, 0);
        check_tx(5);

        repeat(20) @(posedge uart_clk);
        
        // feature6
        drive_and_check_rx(8'hB3, 6);

        // feature7
        drive_and_check_rx(8'b1111_1111, 7);

        // feature8
        drive_and_check_rx(8'b0000_000, 8);

        // feature9
        drive_and_check_rx(8'hC5, 9);
        drive_and_check_rx(8'h7D, 9);
        drive_and_check_rx(8'h4F, 9);

        // feature10
        invalid_start = 1;
        drive_and_check_rx(8'hD9, 10);
        
        $display("\n=== TEST SUMMARY ===");
        $display("PASS: %d / %d", pass_count, total_cases);
        $display("FAIL: %d / %d", total_cases-pass_count, total_cases);

        $finish;
    end
endmodule


