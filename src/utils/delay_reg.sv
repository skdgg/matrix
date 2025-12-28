module delay_reg #(
    parameter SIZE  = 32,
    parameter NUM   = 1,
    parameter DELAY = 4
)(
    input                 clk,
    input                 rst,
    input                 in_valid,
    input  [SIZE*NUM-1:0] data_in,
    output                out_valid,
    output [SIZE*NUM-1:0] data_out
); 

    logic [DELAY-1:0]    valid_reg;
    logic [SIZE*NUM-1:0] data_reg [0:DELAY-1];

    integer i;

    always_ff @(posedge clk) begin
        if(rst) begin
            valid_reg <= 'd0;
            for(i = 0; i < DELAY; i = i + 1) begin
                data_reg[i] <= 'd0;
            end
        end else begin
            valid_reg <= {in_valid, valid_reg[DELAY-1:1]};
            if(in_valid) data_reg[0] <= data_in;
            for(i = 1; i < DELAY; i = i + 1) begin
                data_reg[i] <= data_reg[i-1];
            end
        end
    end

    assign out_valid = valid_reg[0];
    assign data_out  = data_reg[DELAY-1];

endmodule