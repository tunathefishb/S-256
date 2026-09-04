#!/usr/bin/env python3
import os

# Define the directory and file structure
STRUCTURE = {
    "lib": [],
    "include": ["soc_pkg.sv"],
    "core": ["big_core.sv", "little_core.sv"],
    "core/common": [],
    "subsystems": ["compute_cluster.sv"],
    "cache": ["generic_cache.sv", "edram_wrapper.sv"],
    "interconnect": ["interfaces.sv", "ring_node.sv", "ring_adapter.sv"],
    "dsp": ["dsp.sv"],
    "gpu": ["gpu_slice.sv"],
    "io": ["misc_io.sv"],
    "media": ["display_engine.sv", "media_engine.sv", "isp.sv"],
    "memory": ["memory_controller.sv"],
    "system": ["cmu.sv", "interrupt_controller.sv", "sec_enclave.sv"],
    "tb": [],
}

def create_stub(filepath, module_name):
    # Basic stub content
    content = f"module {module_name} (\n"
    content += "    input logic clk,\n"
    content += "    input logic rst_n\n"
    content += ");\n\n"
    content += f"    // TODO: Implement {module_name}\n\n"
    content += f"endmodule\n"
    
    # Specific contents for packages and interfaces
    if filepath.endswith("soc_pkg.sv"):
        content = "package soc_pkg;\n"
        content += "    // Global definitions, structs, and memory maps\n"
        content += "endpackage\n"
    elif filepath.endswith("interfaces.sv"):
        content = "interface ring_bus_if (input logic clk);\n"
        content += "    logic [255:0] data;\n"
        content += "    logic valid;\n"
        content += "    logic ready;\n"
        content += "    modport master(output data, valid, input ready);\n"
        content += "    modport slave(input data, valid, output ready);\n"
        content += "endinterface\n\n"
        content += "interface comms_bus_if (input logic clk);\n"
        content += "    logic [31:0] cmd;\n"
        content += "    logic valid;\n"
        content += "    logic ready;\n"
        content += "    modport master(output cmd, valid, input ready);\n"
        content += "    modport slave(input cmd, valid, output ready);\n"
        content += "endinterface\n"

    if os.path.exists(filepath):
        print(f"  Skipping {filepath} (already exists)")
        return

    with open(filepath, "w") as f:
        f.write(content)

def generate_topology():
    content = "`include \"include/soc_pkg.sv\"\n\n"
    content += "module topology (\n"
    content += "    input logic clk,\n"
    content += "    input logic rst_n\n"
    content += ");\n\n"
    content += "    import soc_pkg::*;\n\n"
    content += "    // Instantiate Interconnect Interfaces\n"
    content += "    ring_bus_if ring_if(.clk(clk));\n"
    content += "    comms_bus_if comms_if(.clk(clk));\n\n"
    content += "    // Subsystems & Compute Cluster\n"
    content += "    compute_cluster u_compute_cluster (\n"
    content += "        .clk(clk),\n"
    content += "        .rst_n(rst_n)\n"
    content += "    );\n\n"
    content += "    // Memory & Caches\n"
    content += "    memory_controller u_mem_ctrl (\n"
    content += "        .clk(clk),\n"
    content += "        .rst_n(rst_n)\n"
    content += "    );\n\n"
    content += "    // Generic Caches (e.g. L3, L4)\n"
    content += "    generic_cache #(.LINE_SIZE(64), .WAYS(8)) u_l3_cache (\n"
    content += "        .clk(clk),\n"
    content += "        .rst_n(rst_n)\n"
    content += "    );\n\n"
    content += "    // GPU Slices\n"
    content += "    gpu_slice u_gpu_0 (\n"
    content += "        .clk(clk),\n"
    content += "        .rst_n(rst_n)\n"
    content += "    );\n\n"
    content += "    // Add remaining component instances here...\n\n"
    content += "endmodule\n"
    
    with open("topology.sv", "w") as f:
        f.write(content)

def main():
    print("Generating S-256 SoC Directory Structure...")
    
    for directory, files in STRUCTURE.items():
        # Create directory
        os.makedirs(directory, exist_ok=True)
        print(f"Created directory: {directory}/")
        
        # Create file stubs
        for file in files:
            filepath = os.path.join(directory, file)
            module_name = file.replace(".sv", "")
            create_stub(filepath, module_name)
            print(f"  Created stub: {filepath}")
            
    # Generate Top level topology
    generate_topology()
    print("Created stub: topology.sv")
    
    print("\nStructure generation complete!")

if __name__ == "__main__":
    main()
