`include "include/soc_pkg.sv"

module topology (
    input logic clk,
    input logic rst_n
);

    import soc_pkg::*;

    // Instantiate Interconnect Interfaces
    ring_bus_if ring_if(.clk(clk));
    comms_bus_if comms_if(.clk(clk));

    // Subsystems & Compute Cluster
    compute_cluster u_compute_cluster (
        .clk(clk),
        .rst_n(rst_n)
    );

    // Memory & Caches
    memory_controller u_mem_ctrl (
        .clk(clk),
        .rst_n(rst_n)
    );

    // Generic Caches (e.g. L3, L4)
    generic_cache #(.LINE_SIZE(64), .WAYS(8)) u_l3_cache (
        .clk(clk),
        .rst_n(rst_n)
    );

    // GPU Slices
    gpu_slice u_gpu_0 (
        .clk(clk),
        .rst_n(rst_n)
    );

    // Add remaining component instances here...

endmodule
