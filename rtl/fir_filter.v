module fir_filter(
	input wire clk,
	input wire rst_n,

	input wire signed [15:0] x_in,
	output reg signed [15:0] y_out

);

	localparam signed [15:0] H0  = 16'shFF3A; // h[0]  = -198
	localparam signed [15:0] H1  = 16'shFD5C; // h[1]  = -676
	localparam signed [15:0] H2  = 16'shFBCA; // h[2]  = -1078
	localparam signed [15:0] H3  = 16'shFC8E; // h[3]  = -882
	localparam signed [15:0] H4  = 16'sh0244; // h[4]  = +580
	localparam signed [15:0] H5  = 16'sh0CC2; // h[5]  = +3266
	localparam signed [15:0] H6  = 16'sh18C2; // h[6]  = +6338
	localparam signed [15:0] H7  = 16'sh20C9; // h[7]  = +8393
	localparam signed [15:0] H8  = 16'sh20C9; // h[8]  = +8393
	localparam signed [15:0] H9  = 16'sh18C2; // h[9]  = +6338
	localparam signed [15:0] H10 = 16'sh0CC2; // h[10] = +3266
	localparam signed [15:0] H11 = 16'sh0244; // h[11] = +580
	localparam signed [15:0] H12 = 16'shFC8E; // h[12] = -882
	localparam signed [15:0] H13 = 16'shFBCA; // h[13] = -1078
	localparam signed [15:0] H14 = 16'shFD5C; // h[14] = -676
	localparam signed [15:0] H15 = 16'shFF3A; // h[15] = -198
	
	
	// accumulator is padded with 4 guard bits
	reg signed [35:0] acc;

	reg signed [15:0] delay_line [14:0];
	integer i;

	always @(posedge clk) begin
		
		if(!rst_n) begin
			// clear all shift registers
			for(i = 0; i < 15; i = i + 1) delay_line[i] <= 16'sh0000;

			// clear output
			y_out <= 16'sh0000;
		end else begin
			delay_line[0] <= x_in; 

			// shift
			for(i = 1; i < 15; i = i + 1) delay_line[i] <= delay_line[i-1];

			// output takes a truncated portion from the accumulator
			y_out <= acc[30:15];
		end
	end

	always @(*) begin
		
		acc = x_in                 * H0;
		acc = acc + delay_line[0]  * H1;
		acc = acc + delay_line[1]  * H2;
		acc = acc + delay_line[2]  * H3;
		acc = acc + delay_line[3]  * H4;
		acc = acc + delay_line[4]  * H5;
		acc = acc + delay_line[5]  * H6;
		acc = acc + delay_line[6]  * H7;
		acc = acc + delay_line[7]  * H8;
		acc = acc + delay_line[8]  * H9;
		acc = acc + delay_line[9]  * H10;
		acc = acc + delay_line[10] * H11;
		acc = acc + delay_line[11] * H12;
		acc = acc + delay_line[12] * H13;
		acc = acc + delay_line[13] * H14;
		acc = acc + delay_line[14] * H15;

	end

endmodule