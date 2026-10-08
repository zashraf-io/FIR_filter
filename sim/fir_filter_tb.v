`timescale 1ns / 1ps
//==============================================================================
// fir_filter_tb.v
// Self-checking testbench for fir_filter (16-tap direct-form FIR, Q1.15).
//
// Runs the 3 required cases back-to-back. For every case it:
//   1. loads stimulus_caseN.hex  and  golden_caseN.hex   ($readmemh)
//   2. resets the DUT (clears the delay line), then drives ONE sample per clock
//   3. compares y_out against the golden model, sample by sample
//
// TIMING (from the interface contract):
//   x_in = x[n] is applied before clock edge n.  y_out is REGISTERED, so the
//   filtered value y[n] shows up on y_out right AFTER that edge  ->  1 cycle
//   of latency.  The check therefore happens one cycle later:
//        compare  y_out  against  golden[n-1]   while driving  stimulus[n].
//
// Inputs are driven on the FALLING clock edge (and y_out is also sampled on the
// falling edge), so nothing ever changes at the same instant as the DUT's
// rising-edge sampling -> no simulation races.
//
// Waveform tips:  x_in, y_out and y_expected are signed 16-bit.  In the viewer
// set their radix to "Decimal (signed)" and the format to "Analog".
// y_expected is the golden value aligned in time with y_out, so the two traces
// should lie exactly on top of each other.
//==============================================================================
module fir_filter_tb;

    // ------------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------------
    localparam NS         = 4800;   // samples per case (must equal Ns in the MATLAB script)
    localparam CLK_PERIOD = 10;     // ns
    localparam MAX_REPORT = 10;     // max mismatches printed per case

    // ------------------------------------------------------------------
    // DUT connections
    // ------------------------------------------------------------------
    reg                clk;
    reg                rst_n;
    reg  signed [15:0] x_in;
    wire signed [15:0] y_out;

    fir_filter dut (
        .clk   (clk),
        .rst_n (rst_n),
        .x_in  (x_in),
        .y_out (y_out)
    );

    // ------------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ------------------------------------------------------------------
    // Data from MATLAB (one extra word so a file that is too LONG is detected)
    // ------------------------------------------------------------------
    reg [15:0] stim [0:NS];
    reg [15:0] gold [0:NS];

    // ------------------------------------------------------------------
    // Bookkeeping + waveform helper signals
    // ------------------------------------------------------------------
    integer           case_id;        // which case is running (0 = none)
    integer           samp_idx;       // index of the sample being captured this clock
    reg               samp_valid;     // 1 while real samples are being driven
    reg signed [15:0] y_expected;     // golden value, aligned in time with y_out
    integer           total_errors;
    integer           case_errors;
    reg               files_ok;

    // Updated on the same rising edge on which the DUT captures y[n], so
    // y_expected and y_out change together and can be overlaid in the viewer.
    always @(posedge clk) begin
        if (samp_valid) y_expected <= gold[samp_idx];
        else            y_expected <= 16'sd0;
    end

    // ------------------------------------------------------------------
    // Run one test case
    // ------------------------------------------------------------------
    task run_case;
        input integer id;
        integer n;
        begin
            case_id     = id;
            case_errors = 0;
            samp_valid  = 1'b0;
            samp_idx    = 0;
            files_ok    = 1'b1;

            // Fill the memories with X first, so a file that is too short
            // (or too long) cannot be hidden by data left over from the previous case.
            for (n = 0; n <= NS; n = n + 1) begin
                stim[n] = 16'hxxxx;
                gold[n] = 16'hxxxx;
            end

            case (id)
                1: begin
                    $readmemh("hex/stimulus_case1.hex", stim);
                    $readmemh("hex/golden_case1.hex",   gold);
                    $display("---- Case 1: 1 kHz + 18 kHz (interferer in the STOPBAND, should be removed) ----");
                end
                2: begin
                    $readmemh("hex/stimulus_case2.hex", stim);
                    $readmemh("hex/golden_case2.hex",   gold);
                    $display("---- Case 2: 1 kHz + 7 kHz (interferer in the TRANSITION band, partly reduced) ----");
                end
                3: begin
                    $readmemh("hex/stimulus_case3.hex", stim);
                    $readmemh("hex/golden_case3.hex",   gold);
                    $display("---- Case 3: 1 kHz + 3 kHz (both in the PASSBAND, both should pass) ----");
                end
                default: begin
                    $display("ERROR: unknown case %0d", id);
                    files_ok = 1'b0;
                end
            endcase

            // File length sanity check: exactly NS words expected.
            if (^stim[NS-1] === 1'bx || ^gold[NS-1] === 1'bx) begin
                $display("ERROR: case %0d hex files have fewer than %0d lines (or are missing).", id, NS);
                files_ok = 1'b0;
            end
            if (^stim[NS] !== 1'bx || ^gold[NS] !== 1'bx) begin
                $display("ERROR: case %0d hex files have MORE than %0d lines - NS does not match MATLAB's Ns.", id, NS);
                files_ok = 1'b0;
            end

            if (!files_ok) begin
                case_errors  = case_errors + 1;
                total_errors = total_errors + 1;
                $display("Case %0d: FAIL (bad input files)", id);
            end else begin
                // ---- reset: clears the delay line and y_out ----
                @(negedge clk);
                rst_n = 1'b0;
                x_in  = 16'sd0;
                repeat (3) @(negedge clk);

                // ---- drive NS samples, then one extra cycle to check the last one ----
                for (n = 0; n <= NS; n = n + 1) begin

                    // y_out now holds the response to the PREVIOUS sample (n-1)
                    if (n > 0) begin
                        if (y_out !== gold[n-1]) begin
                            case_errors  = case_errors + 1;
                            total_errors = total_errors + 1;
                            if (case_errors <= MAX_REPORT)
                                $display("  MISMATCH case %0d, sample %0d: y_out = %0d, expected = %0d",
                                          id, n-1, y_out, $signed(gold[n-1]));
                        end
                    end

                    // drive the next sample (or stop driving after the last one)
                    if (n < NS) begin
                        samp_idx   = n;
                        samp_valid = 1'b1;
                        rst_n      = 1'b1;       // reset is released together with sample 0
                        x_in       = stim[n];
                    end else begin
                        samp_valid = 1'b0;
                        x_in       = 16'sd0;
                    end

                    @(negedge clk);
                end

                if (case_errors == 0)
                    $display("Case %0d: PASS  (%0d / %0d samples match the golden model)", id, NS, NS);
                else
                    $display("Case %0d: FAIL  (%0d mismatching samples out of %0d)", id, case_errors, NS);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Main sequence
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("fir_filter_tb.vcd");
        $dumpvars(0, fir_filter_tb);

        total_errors = 0;
        case_id      = 0;
        samp_idx     = 0;
        samp_valid   = 1'b0;
        y_expected   = 16'sd0;
        rst_n        = 1'b0;
        x_in         = 16'sd0;

        repeat (2) @(negedge clk);

        run_case(1);
        run_case(2);
        run_case(3);

        case_id = 0;
        repeat (4) @(negedge clk);

        $display("==================================================");
        if (total_errors == 0)
            $display("ALL 3 CASES PASSED - RTL output matches the MATLAB golden model.");
        else
            $display("TEST FAILED - %0d mismatches in total.", total_errors);
        $display("==================================================");
        $finish;
    end

endmodule
