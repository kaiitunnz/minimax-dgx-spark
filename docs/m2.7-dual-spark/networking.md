# Networking — Dual-DGX-Spark ConnectX-7 setup

Re-run `scripts/verify-cluster.sh` after any hardware or driver change.

## Topology

Two DGX Sparks, each with two ConnectX-7 cards × two ports = four RoCE links per node. The links form two `/24` fabrics; each fabric carries traffic from both cards' matching ports.

| | Head | Worker |
| --- | --- | --- |
| LAN | `10.0.0.10` (`<lan-if>`) | `10.0.0.11` (`<lan-if>`) |
| Card 1 port 0 (`enp1s0f0np0`) | `10.0.100.10` | `10.0.100.11` |
| Card 1 port 1 (`enp1s0f1np1`) | `10.0.200.10` | `10.0.200.11` |
| Card 2 port 0 (`enP2p1s0f0np0`) | `10.0.100.20` | `10.0.100.21` |
| Card 2 port 1 (`enP2p1s0f1np1`) | `10.0.200.20` | `10.0.200.21` |

The fabric IPs above are illustrative. Pick two `/24`s for the RoCE fabrics, with each card's matching port (0 / 1) on the same fabric. `<lan-if>` is the LAN NIC on the host (it shows up in `ip -br link` as the only non-RoCE NIC).

`.env.example` configures the full 4-cable mesh via `IB_IF`. mDNS resolves the worker's `.local` name on every fabric; ARP learning is established at boot.

## Mandatory configuration

### MTU 9000 on every RoCE port

NCCL silently degrades to TCP fallback or drops packets at MTU 1500. The host helper `~/scripts/mtu-fixup.sh` (not in this repo — host-setup tool) bumps live MTU via `ip link set ... mtu 9000` and writes a netplan drop-in (`/etc/netplan/99-roce-mtu-9000.yaml`) for persistence across reboots. Run on each node:

```bash
sudo ~/scripts/mtu-fixup.sh
```

Then re-run `./scripts/verify-cluster.sh` from the head; the MTU section must show `mtu 9000` on every interface on every node.

### NVIDIA driver 580.x

Driver 590.x triggers a CUDA-graph deadlock during NCCL bring-up on GB10. Both nodes must be on a 580.x release. Aligning the minor version is not required but is worth doing if either node hits an obscure NCCL issue.

### Passwordless SSH between nodes

The eugr launcher SSHes from head to worker without prompts. The setup helper `~/scripts/discover-sparks.sh` (also host-scoped, not in this repo) generates `~/.ssh/id_ed25519_shared` and distributes it across the cluster. To verify:

```bash
ssh -o BatchMode=yes <worker-host> hostname
```

Must print the worker's hostname without a password or key-passphrase prompt.

## `IB_IF` — HCA names, not netdev names

`IB_IF` in `.env` is passed verbatim into `NCCL_IB_HCA` inside the container. **NCCL_IB_HCA wants the InfiniBand HCA names** (column 1 of `ibdev2netdev`), not the matching netdev names (column 5). Mixing them up gives this failure mode:

```
NCCL INFO NET/IB : No device found.
NCCL INFO Failed to initialize NET plugin IB
NCCL INFO NET/Socket : Using [0]<lan-if>:<head-ip><0>
```

NCCL falls back to TCP socket silently — the cluster appears to work, throughput is 10–20× slower than expected.

For our dual-Spark mesh, the correct value (matching what eugr's autodiscover hardcodes for a 4-cable setup):

```
IB_IF=rocep1s0f0,roceP2p1s0f0,rocep1s0f1,roceP2p1s0f1
```

`scripts/verify-cluster.sh` maps each HCA to its netdev via `ibdev2netdev` for the MTU and ping checks.

## NCCL environment

Set via `CONTAINER_*` keys in `.env`; the launcher forwards them as `-e FOO=bar` into the container (stripping the `CONTAINER_` prefix).

| Variable | Value | Why |
| --- | --- | --- |
| `CONTAINER_NCCL_IGNORE_CPU_AFFINITY` | `1` | Avoid CPU-affinity churn that stalls NCCL on Grace |
| `CONTAINER_NCCL_DMABUF_ENABLE` | `1` | Use DMA-BUF GPUDirect path on GB10; ~22 GB/s effective. Falls back to CPU staging if unavailable |
| `CONTAINER_NCCL_IB_GID_INDEX` | `3` | RoCE v2 GID index per NVIDIA's DGX Spark playbook |
| `CONTAINER_NCCL_DEBUG` | `INFO` | Surface transport selection during bring-up; can be dropped once stable |

`NCCL_IB_HCA` and `NCCL_SOCKET_IFNAME` are derived by the launcher from `IB_IF` / `ETH_IF` in `.env`.

## Verification

```bash
./scripts/verify-cluster.sh                       # full preflight
ssh <worker-host> ibdev2netdev                    # confirm peer's RoCE state
ping -I enP2p1s0f0np0 <worker-fabric1-card2-ip>   # RoCE fabric 1 ping
ping -I enP2p1s0f1np1 <worker-fabric2-card2-ip>   # RoCE fabric 2 ping
```

In container logs, `NCCL_DEBUG=INFO` should print a line like:

```
NCCL INFO Using network IB
```

If it prints `Using network Socket` instead, NCCL has fallen back to TCP — fix `NCCL_IB_HCA`, `NCCL_SOCKET_IFNAME`, or the underlying RoCE link before continuing. The first symptom is a 10–20× slowdown across the wire.
