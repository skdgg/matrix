`timescale 1ns/10ps
`define CYCLE 1.0

`ifdef SYN
`include "../syn/top_syn.v"
`include "/opt/CIC/Cell_Libraries/ADFP/Executable_Package/Collaterals/IP/stdcell/N16ADFP_StdCell/VERILOG/N16ADFP_StdCell.v"
`else
`include "../src/vertex_processing.sv"
`endif

module vertex_tb;

    // -------------------------
    // Clock / Reset
    // -------------------------
    logic clk, rst;
    initial clk = 0;
    always #(`CYCLE/2) clk = ~clk;

    initial begin
        `ifdef SYN
            $display("[TB] SYN mode");
            $sdf_annotate("../syn/top_syn.sdf", u_dut);
        `else
            $display("[TB] RTL mode");
        `endif
        `ifdef FSDB_ALL
            $fsdbDumpfile("vertex_processing.fsdb");
            $fsdbDumpvars(0, vertex_tb);
            $fsdbDumpMDA();
        `endif
    end

    // -------------------------
    // Interface Signals
    // -------------------------
    logic         v_valid_i;
    logic  [31:0] Vx_i, Vy_i, Vz_i;
    logic  [31:0] Nx_i, Ny_i, Nz_i;

    logic         Lp_valid_i;
    logic  [31:0] Lpx_i, Lpy_i, Lpz_i;
    logic  [31:0] Lp_intensity_i;

    logic         Ld_valid_i;
    logic  [31:0] Ldx_i, Ldy_i, Ldz_i;
    logic  [31:0] Ld_intensity_i;

    logic         La_valid_i;
    logic  [31:0] La_intensity_i;

    logic         m_valid_i;
    logic  [31:0] m00_i, m01_i, m02_i, m03_i;
    logic  [31:0] m10_i, m11_i, m12_i, m13_i;
    logic  [31:0] m20_i, m21_i, m22_i, m23_i;
    logic  [31:0] m30_i, m31_i, m32_i, m33_i;

    logic         P_scale_valid_i;
    logic  [31:0] Px_scale_i, Py_scale_i;

    logic         out_valid_o;
    logic [31:0] Px_o, Py_o, Pz_inv_o;
    logic [31:0] brightness_o;

    // -------------------------
    // DUT Instantiation
    // -------------------------
    vertex_processing u_dut (
        .clk(clk),
        .rst(rst),

        .v_valid_i(v_valid_i),
        .Vx_i(Vx_i), .Vy_i(Vy_i), .Vz_i(Vz_i),
        .Nx_i(Nx_i), .Ny_i(Ny_i), .Nz_i(Nz_i),

        .Lp_valid_i(Lp_valid_i),
        .Lpx_i(Lpx_i), .Lpy_i(Lpy_i), .Lpz_i(Lpz_i),
        .Lp_intensity_i(Lp_intensity_i),

        .Ld_valid_i(Ld_valid_i),
        .Ldx_i(Ldx_i), .Ldy_i(Ldy_i), .Ldz_i(Ldz_i),
        .Ld_intensity_i(Ld_intensity_i),

        .La_valid_i(La_valid_i),
        .La_intensity_i(La_intensity_i),

        .m_valid_i(m_valid_i),
        .m00_i(m00_i), .m01_i(m01_i), .m02_i(m02_i), .m03_i(m03_i),
        .m10_i(m10_i), .m11_i(m11_i), .m12_i(m12_i), .m13_i(m13_i),
        .m20_i(m20_i), .m21_i(m21_i), .m22_i(m22_i), .m23_i(m23_i),
        .m30_i(m30_i), .m31_i(m31_i), .m32_i(m32_i), .m33_i(m33_i),

        .P_scale_valid_i(P_scale_valid_i),
        .Px_scale_i(Px_scale_i), .Py_scale_i(Py_scale_i),

        .out_valid_o(out_valid_o),
        .Px_o(Px_o), .Py_o(Py_o), .Pz_inv_o(Pz_inv_o),
        .brightness_o(brightness_o)
    );

    // -------------------------
    // Testbench Logic
    // -------------------------
    logic [31:0] input_mem [0:200000];
    logic [31:0] golden_mem [0:200000];
    integer num_vertices;
    integer input_ptr;
    integer golden_ptr;
    integer out_cnt;
    integer err_cnt;
    integer i;

    // Helper to compare float with tolerance
    function bit is_close(input [31:0] a, input [31:0] b);
        shortreal fa, fb, diff;
        fa = $bitstoshortreal(a);
        fb = $bitstoshortreal(b);
        diff = fa - fb;
        if (diff < 0) diff = -diff;
        // Tolerance: 0.05
        if (diff < 0.05) return 1; 
        return 0;
    endfunction

    initial begin
        // Load files
        $readmemh("../sim/vertex/test_vertex/input.hex", input_mem);
        $readmemh("../sim/vertex/test_vertex/golden_output.hex", golden_mem);

        num_vertices = input_mem[0];
        $display("Number of vertices: %d", num_vertices);

        // Initialize signals
        rst = 1;
        v_valid_i = 0;
        Lp_valid_i = 0;
        Ld_valid_i = 0;
        La_valid_i = 0;
        m_valid_i = 0;
        P_scale_valid_i = 0;
        
        // Reset sequence
        #(`CYCLE*2);
        rst = 0;
        #(`CYCLE);

        input_ptr = 28;
        for (i = 0; i < num_vertices; i++) begin
            @(posedge clk) #0.1;

            // Drive Global Parameters simultaneously with the first vertex
            if (i == 0) begin
                // Model-view matrix
                m_valid_i = 1;
                m00_i = input_mem[1]; m01_i = input_mem[2]; m02_i = input_mem[3]; m03_i = input_mem[4];
                m10_i = input_mem[5]; m11_i = input_mem[6]; m12_i = input_mem[7]; m13_i = input_mem[8];
                m20_i = input_mem[9]; m21_i = input_mem[10]; m22_i = input_mem[11]; m23_i = input_mem[12];
                m30_i = input_mem[13]; m31_i = input_mem[14]; m32_i = input_mem[15]; m33_i = input_mem[16];

                // Position light
                Lp_valid_i = 1;
                Lpx_i = input_mem[17]; Lpy_i = input_mem[18]; Lpz_i = input_mem[19];
                Lp_intensity_i = input_mem[23];

                // Direction light
                Ld_valid_i = 1;
                Ldx_i = input_mem[20]; Ldy_i = input_mem[21]; Ldz_i = input_mem[22];
                Ld_intensity_i = input_mem[24];

                // Ambient light
                La_valid_i = 1;
                La_intensity_i = input_mem[25];

                // Projection scale
                P_scale_valid_i = 1;
                Px_scale_i = input_mem[26];
                Py_scale_i = input_mem[27];
            end

            v_valid_i = 1;
            // Format: ID, Vx, Vy, Vz, Vw, Nx, Ny, Nz
            // Skip ID (input_ptr)
            Vx_i = input_mem[input_ptr+1];
            Vy_i = input_mem[input_ptr+2];
            Vz_i = input_mem[input_ptr+3];
            // Skip Vw (input_ptr+4)
            Nx_i = input_mem[input_ptr+5];
            Ny_i = input_mem[input_ptr+6];
            Nz_i = input_mem[input_ptr+7];
            
            input_ptr = input_ptr + 8;
        end

        @(posedge clk) #0.1;
        v_valid_i = 0;
        
        // Wait for completion
        #(`CYCLE * 1000); // Timeout
        if (out_cnt != num_vertices) begin
            $display("Timeout: Expected %d outputs, got %d", num_vertices, out_cnt);
        end
        $finish;
    end

    // Monitor Process
    initial begin
        out_cnt = 0;
        err_cnt = 0;
        golden_ptr = 1;
        
        forever begin
            @(posedge clk);
            if (out_valid_o) begin
                logic [31:0] exp_Px, exp_Py, exp_Pz_inv, exp_Br;
                exp_Px = golden_mem[golden_ptr];
                exp_Py = golden_mem[golden_ptr+1];
                exp_Pz_inv = golden_mem[golden_ptr+2];
                exp_Br = golden_mem[golden_ptr+3];
                
                // Compare
                `ifdef TOL
                if (!is_close(Px_o, exp_Px)) begin
                `else 
                if (Px_o != exp_Px) begin
                `endif
                    $display("Error at vertex %d: Px mismatch. Exp: %h (%f), Got: %h (%f)", 
                        out_cnt, exp_Px, $bitstoshortreal(exp_Px), Px_o, $bitstoshortreal(Px_o));
                    err_cnt++;
                end
                `ifdef TOL
                if (!is_close(Py_o, exp_Py)) begin
                `else 
                if (Py_o != exp_Py) begin
                `endif
                    $display("Error at vertex %d: Py mismatch. Exp: %h (%f), Got: %h (%f)", 
                        out_cnt, exp_Py, $bitstoshortreal(exp_Py), Py_o, $bitstoshortreal(Py_o));
                    err_cnt++;
                end
                `ifdef TOL
                if (!is_close(Pz_inv_o, exp_Pz_inv)) begin
                `else 
                if (Pz_inv_o != exp_Pz_inv) begin
                `endif
                    $display("Error at vertex %d: Pz_inv mismatch. Exp: %h (%f), Got: %h (%f)", 
                        out_cnt, exp_Pz_inv, $bitstoshortreal(exp_Pz_inv), Pz_inv_o, $bitstoshortreal(Pz_inv_o));
                    err_cnt++;
                end
                `ifdef TOL
                if (!is_close(brightness_o, exp_Br)) begin
                `else 
                if (brightness_o != exp_Br) begin
                `endif
                    $display("Error at vertex %d: Brightness mismatch. Exp: %h (%f), Got: %h (%f)", 
                        out_cnt, exp_Br, $bitstoshortreal(exp_Br), brightness_o, $bitstoshortreal(brightness_o));
                    err_cnt++;
                end

                golden_ptr = golden_ptr + 4;
                out_cnt++;
                
                if (out_cnt == num_vertices) begin
                    $display("------------------------------------------------------------");
                    $display("Vertex Processing simulation done!");
                    if (err_cnt == 0) begin
                        $display("  ALL PASS!");
                    end else begin
                        $display("  FAILED with %d errors.", err_cnt);  
                    end
                    $display("------------------------------------------------------------");
                end
            end
        end
    end

endmodule
