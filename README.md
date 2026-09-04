# S-256 SoC Architecture

## Overview
The S-256 is a custom System on a Chip (SoC) architecture currently in its initial structural design phase. The project contains a scalable, hierarchical directory structure featuring modular Verilog stubs for various SoC components. It includes a Python-based generator for rapid prototyping of the interconnects and topology wrappers.

## Project Structure
The repository is organized into distinct logical domains using SystemVerilog (`.sv`):

- **`topology.sv`**: The top-level module instantiating major subsystems and laying the groundwork for the global ring and command bus connections.
- **`generate_stubs.py`**: A Python automation script used to regenerate the boilerplate SystemVerilog `.sv` stubs and the full hierarchical directory structure.
- **`include/`**: Contains global definitions like `soc_pkg.sv` for memory maps, parameters, and structs.
- **`lib/`**: Shared IPs like FIFOs, arbiters, SRAM wrappers, and CDC logic.
- **`core/`**: CPU components featuring a heterogeneous layout of Big Cores (`big_core.sv`) and Little Cores (`little_core.sv`), with a `common/` subdirectory for shared logic like ALUs and Decoders.
- **`subsystems/`**: Hierarchical wrappers. Currently contains `compute_cluster.sv` which wraps the cores, CMU, and L2 caches together to simplify top-level wiring.
- **`cache/`**: The SoC's deep cache hierarchy utilizing a parameterized `generic_cache.sv` and `edram_wrapper.sv` for the fast eDRAM modules designed to relieve ring bus congestion.
- **`interconnect/`**: SystemVerilog interfaces (`interfaces.sv`), generic ring logic (`ring_node.sv`), and adapters (`ring_adapter.sv`).
- **`gpu/`**: GPU domains (`gpu_slice.sv`), physically split into two slices across the chip.
- **`media/`**: Multimedia engines including Display Engine (`display_engine.sv`), Media Engine (`media_engine.sv`), and ISP (`isp.sv`).
- **`system/`**: Core system logic such as the Central Management Unit (`cmu.sv`), Interrupt Controller (`interrupt_controller.sv`), and Secure Enclave (`sec_enclave.sv`).
- **`memory/`**: The main Memory Controller (`memory_controller.sv`).
- **`dsp/`**: Digital Signal Processor blocks (`dsp.sv`).
- **`io/`**: Miscellaneous I/O interfaces (`misc_io.sv`).
- **`tb/`**: Testbenches for isolated debugging.

## Physical Die Layout & Architecture Highlights

```text
+-----------------------------------------------------------------------+
|                              Misc I/O                                 |
+-------+-------------------------------------------------------+-------+
|       |                       L4 Cache                        |       |
|       +-------+---------------------------------------+-------+       |
|  GPU  | eDRAM |          Memory Controller            | eDRAM |  GPU  |
| Slice +-------+---------------------------------------+-------+ Slice |
|   0   |     ================ RING BUS ================        |   1   |
|       +-------------------------------------------------------+       |
|       |          +---------------------------------+          |       |
|       |          |            L3 Cache             |          |       |
|       |          |          (3D Stacked)           |          |       |
|       |          |---------------------------------|          |       |
|       |          |    L2 Cache     |    L2 Cache   |          |       |
|       |          |   (Big Cores)   | (Little Cores)|          |       |
|       |          |---------------------------------|          |       |
|       |          | B0 | B1 | B2| B3| L0 - L3|L4 -L7|          |       |
|       |          +---------------------------------+          |       |
|       +-------------------------------------------------------+       |
|       |    Media Engines     |    System Logic    |    DSP    |       |
|       | (Display, Media, ISP)|  (CMU, Int, SecEn) |           |       |
+-------+-------------------------------------------------------+-------+
```

The S-256 design places a heavy emphasis on mitigating physical routing congestion and thermal hotspots through careful floorplanning:
- **Centralized CPU & Cache Cluster**: The asymmetrical core cluster (4 Big, 8 Little) is positioned centrally.
- **Advanced 3D Caching**: Incorporates an innovative 3D-stacked L3 cache positioned directly over the L2s in 3D space, preserving 2D die area while offering massive bandwidth.
- **Distributed Edge GPU**: The GPU is physically split into two slices situated on the far left and right edges of the die. This prevents thermal concentration and avoids routing a massive GPU-to-GPU bus over the central CPU cluster. Despite the physical split, it operates as a single unified logical GPU.
- **Ring Bus Topology**: On-chip communication is handled via a high-bandwidth 256-bit bidirectional ring data bus alongside a dedicated 32-bit command and control bus.
- **Strategic L4 & eDRAM Placement**: The large L4 cache sits close to the memory controller, interacting heavily with the main ring data bus. To prevent ring bus saturation, small, fast eDRAM modules are placed strategically to offload and cache less time-sensitive data, relieving pressure from the main data ring.

## Getting Started
The current files represent the structural layout of the SoC with boilerplate logic.
To regenerate or modify the module instances, bus widths, or overall topology:
1. Modify the `modules` and `instances` dictionaries in `generate_stubs.py`.
2. Run the generator script:
   ```bash
   python3 generate_stubs.py
   ```
3. This will instantly regenerate the directory tree, `.sv` file stubs, and the complete `topology.sv` file.

## Next Steps
- Interconnect wiring implementation within `topology.sv`.
- Implementation of internal logic and RTL for individual IPs, starting from the generated stubs.
- Validation of Ring Bus and Command Bus bandwidth capabilities under load.
