// project2.gleam - Enhanced Gossip Protocol with Convergence Monitoring
import envoy
import gleam/bool
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import gleam/set.{type Set}
import gleam/string
import gleam/time/duration.{type Duration}
import gleam/time/timestamp

// Types for our algorithms
pub type Algorithm {
  Gossip
  PushSum
}

pub type Topology {
  Full
  ThreeD
  Line
  Imperfect3D
}

// Enhanced Gossip Message types
pub type GossipMessage {
  Rumor(content: String, sender_id: Int)
  SetNeighbors(neighbors: List(process.Subject(GossipMessage)))
  SetSupervisor(supervisor: process.Subject(ConvergenceMessage))
  Shutdown
  GetStatus
}

pub type GossipState {
  GossipState(
    id: Int,
    neighbors: List(process.Subject(GossipMessage)),
    rumor_count: Int,
    has_rumor: Bool,
    rumor_content: String,
    total_nodes: Int,
    terminated: Bool,
    supervisor: option.Option(process.Subject(ConvergenceMessage)),
  )
}

// Convergence Monitor types
pub type ConvergenceMessage {
  NodeFirstHeardRumor(node_id: Int)
  NodeTerminated(node_id: Int)
  CheckConvergenceStatus
  GetConvergenceResult(reply_to: process.Subject(ConvergenceResult))
  StartMonitoring
  StopMonitoring
}

pub type ConvergenceState {
  ConvergenceState(
    total_nodes: Int,
    nodes_with_rumor: Set(Int),
    terminated_nodes: Set(Int),
    convergence_achieved: Bool,
    convergence_time: option.Option(Int),
    start_time: Int,
    convergence_threshold: Float,
    topology: Topology,
    monitoring_active: Bool,
  )
}

pub type ConvergenceResult {
  ConvergenceResult(
    converged: Bool,
    time_to_convergence: option.Option(Int),
    coverage_percentage: Float,
    nodes_with_rumor: Int,
    total_nodes: Int,
    terminated_nodes: Int,
  )
}

// 3D Position type for topology building
pub type Position3D {
  Position3D(x: Int, y: Int, z: Int)
}

// Push-Sum types (for future use)
pub type PushSumMessage {
  PushSumPair(s: Float, w: Float, sender_id: Int)
  PushSumShutdown
}

pub type PushSumState {
  PushSumState(
    id: Int,
    neighbors: List(process.Subject(PushSumMessage)),
    s: Float,
    w: Float,
    prev_ratios: List(Float),
    total_nodes: Int,
    active: Bool,
  )
}

// CONVERGENCE MONITOR IMPLEMENTATION
pub fn start_convergence_monitor(
  total_nodes: Int,
  topology: Topology,
) -> Result(process.Subject(ConvergenceMessage), actor.StartError) {
  let threshold = get_convergence_threshold(topology)
  let initial_state =
    ConvergenceState(
      total_nodes: total_nodes,
      nodes_with_rumor: set.new(),
      terminated_nodes: set.new(),
      convergence_achieved: False,
      convergence_time: None,
      start_time: 0,
      convergence_threshold: threshold,
      topology: topology,
      monitoring_active: False,
    )

  case
    actor.new(initial_state)
    |> actor.on_message(handle_convergence_message)
    |> actor.start()
  {
    Ok(started) -> Ok(started.data)
    Error(e) -> Error(e)
  }
}

pub fn handle_convergence_message(
  state: ConvergenceState,
  message: ConvergenceMessage,
) -> actor.Next(ConvergenceState, ConvergenceMessage) {
  case message {
    StartMonitoring -> {
      io.println("Convergence Monitor: Starting to monitor network convergence")
      let start_time = get_current_time_ms()
      let updated_state =
        ConvergenceState(
          ..state,
          monitoring_active: True,
          start_time: start_time,
        )
      actor.continue(updated_state)
    }

    NodeFirstHeardRumor(node_id) -> {
      case state.monitoring_active {
        True -> {
          let updated_nodes = set.insert(state.nodes_with_rumor, node_id)
          let coverage =
            int.to_float(set.size(updated_nodes))
            /. int.to_float(state.total_nodes)

          io.println(
            "📢 Node " <> int.to_string(node_id) <> " heard rumor for FIRST time",
          )
          io.println(
            "   Coverage: "
            <> int.to_string(set.size(updated_nodes))
            <> "/"
            <> int.to_string(state.total_nodes)
            <> " = "
            <> float.to_string(coverage *. 100.0)
            <> "%",
          )

          case
            coverage >=. state.convergence_threshold
            && !state.convergence_achieved
          {
            True -> {
              let current_time = get_current_time_ms()
              let elapsed = current_time - state.start_time

              io.println("🎉 CONVERGENCE ACHIEVED!")
              io.println(
                "   Time to convergence: " <> int.to_string(elapsed) <> "ms",
              )
              io.println(
                "   Final coverage: "
                <> float.to_string(coverage *. 100.0)
                <> "%",
              )
              io.println("   Topology: " <> topology_to_string(state.topology))

              let converged_state =
                ConvergenceState(
                  ..state,
                  nodes_with_rumor: updated_nodes,
                  convergence_achieved: True,
                  convergence_time: Some(elapsed),
                )
              actor.continue(converged_state)
            }
            False -> {
              let updated_state =
                ConvergenceState(..state, nodes_with_rumor: updated_nodes)
              actor.continue(updated_state)
            }
          }
        }
        False -> {
          io.println("⚠️ Received NodeFirstHeardRumor but monitoring not active")
          actor.continue(state)
        }
      }
    }

    NodeTerminated(node_id) -> {
      let updated_terminated = set.insert(state.terminated_nodes, node_id)
      let terminated_count = set.size(updated_terminated)

      io.println("💀 Node " <> int.to_string(node_id) <> " terminated")
      io.println(
        "   Terminated nodes: "
        <> int.to_string(terminated_count)
        <> "/"
        <> int.to_string(state.total_nodes),
      )

      let updated_state =
        ConvergenceState(..state, terminated_nodes: updated_terminated)
      actor.continue(updated_state)
    }

    CheckConvergenceStatus -> {
      let coverage =
        int.to_float(set.size(state.nodes_with_rumor))
        /. int.to_float(state.total_nodes)
      let terminated_count = set.size(state.terminated_nodes)

      io.println("📊 CONVERGENCE STATUS:")
      io.println(
        "   Nodes with rumor: "
        <> string.inspect(set.to_list(state.nodes_with_rumor))
        <> "/"
        <> int.to_string(state.total_nodes)
        <> " ("
        <> float.to_string(coverage *. 100.0)
        <> "%)",
      )
      // io.println(
      //   "   Nodes with rumor: "
      //   <> int.to_string(set.size(state.nodes_with_rumor))
      //   <> "/"
      //   <> int.to_string(state.total_nodes)
      //   <> " ("
      //   <> float.to_string(coverage *. 100.0)
      //   <> "%)",
      // )
      io.println(
        "   Terminated nodes: "
        <> int.to_string(terminated_count)
        <> "/"
        <> int.to_string(state.total_nodes),
      )
      io.println("   Converged: " <> bool_to_string(state.convergence_achieved))

      case state.convergence_achieved {
        True -> {
          case state.convergence_time {
            Some(time) ->
              io.println("   Convergence time: " <> int.to_string(time) <> "ms")
            None -> io.println("   Convergence time: Unknown")
          }
        }
        False -> {
          case state.monitoring_active {
            True -> {
              let current_time = get_current_time_ms()
              let elapsed = current_time - state.start_time
              io.println("   Running time: " <> int.to_string(elapsed) <> "ms")
            }
            False -> io.println("   Monitoring not started")
          }
        }
      }

      actor.continue(state)
    }

    GetConvergenceResult(reply_to) -> {
      let coverage =
        int.to_float(set.size(state.nodes_with_rumor))
        /. int.to_float(state.total_nodes)
      let result =
        ConvergenceResult(
          converged: state.convergence_achieved,
          time_to_convergence: state.convergence_time,
          coverage_percentage: coverage,
          nodes_with_rumor: set.size(state.nodes_with_rumor),
          total_nodes: state.total_nodes,
          terminated_nodes: set.size(state.terminated_nodes),
        )

      process.send(reply_to, result)
      actor.continue(state)
    }

    StopMonitoring -> {
      let final_state = ConvergenceState(..state, monitoring_active: False)
      actor.continue(final_state)
    }
  }
}

fn get_convergence_threshold(topology: Topology) -> Float {
  case topology {
    Full -> 0.98
    // 98% - should reach almost everyone
    Imperfect3D -> 0.95
    // 95% - good connectivity  
    ThreeD -> 0.9
    // 90% - some nodes might be isolated
    Line -> 0.8
    // 80% - line topology is fragile
  }
}

// ENHANCED GOSSIP ACTOR IMPLEMENTATION
pub fn start_gossip_actor_with_supervisor(
  id: Int,
  total_nodes: Int,
) -> Result(process.Subject(GossipMessage), actor.StartError) {
  let initial_state =
    GossipState(
      id: id,
      neighbors: [],
      rumor_count: 0,
      has_rumor: False,
      rumor_content: "",
      total_nodes: total_nodes,
      terminated: False,
      supervisor: None,
    )

  case
    actor.new(initial_state)
    |> actor.on_message(handle_gossip_message_with_supervisor)
    |> actor.start()
  {
    Ok(started) -> Ok(started.data)
    Error(e) -> Error(e)
  }
}

pub fn handle_gossip_message_with_supervisor(
  state: GossipState,
  message: GossipMessage,
) -> actor.Next(GossipState, GossipMessage) {
  case message {
    SetNeighbors(new_neighbors) -> {
      let updated_state = GossipState(..state, neighbors: new_neighbors)
      actor.continue(updated_state)
    }

    SetSupervisor(supervisor) -> {
      io.println(
        "Node " <> int.to_string(state.id) <> " received supervisor reference",
      )
      let updated_state = GossipState(..state, supervisor: Some(supervisor))
      actor.continue(updated_state)
    }

    Rumor(content, sender_id) -> {
      case state.terminated {
        True -> actor.continue(state)
        False -> {
          let is_first_time = !state.has_rumor
          let new_count = case state.has_rumor {
            True -> state.rumor_count + 1
            False -> 1
          }

          let new_state =
            GossipState(
              ..state,
              has_rumor: True,
              rumor_content: content,
              rumor_count: new_count,
            )

          // Report to supervisor if first time hearing
          case is_first_time, state.supervisor {
            True, Some(supervisor) -> {
              io.println(
                "🎯 Node "
                <> int.to_string(state.id)
                <> " heard rumor for FIRST time from Node "
                <> int.to_string(sender_id),
              )
              process.send(supervisor, NodeFirstHeardRumor(state.id))
            }
            _, _ -> Nil
          }

          // Check termination condition
          case new_count >= 10 {
            True -> {
              io.println(
                "💀 Node "
                <> int.to_string(state.id)
                <> " terminating after hearing rumor "
                <> int.to_string(new_count)
                <> " times",
              )

              case state.supervisor {
                Some(supervisor) ->
                  process.send(supervisor, NodeTerminated(state.id))
                None -> Nil
              }

              let terminated_state = GossipState(..new_state, terminated: True)
              actor.continue(terminated_state)
            }
            False -> {
              spread_rumor(new_state)
              actor.continue(new_state)
            }
          }
        }
      }
    }

    Shutdown -> {
      io.println("Node " <> int.to_string(state.id) <> " shutting down")
      actor.stop()
    }

    GetStatus -> {
      io.println(
        "Node "
        <> int.to_string(state.id)
        <> " - Rumor count: "
        <> int.to_string(state.rumor_count)
        <> ", Terminated: "
        <> bool_to_string(state.terminated),
      )
      actor.continue(state)
    }
  }
}

fn spread_rumor(state: GossipState) -> Nil {
  case state.neighbors {
    [] -> Nil
    [single_neighbor] -> {
      let rumor_message = Rumor(state.rumor_content, state.id)
      process.send(single_neighbor, rumor_message)
    }
    multiple_neighbors -> {
      let neighbor_count = list.length(multiple_neighbors)
      let random_index = int.random(neighbor_count)

      case list.drop(multiple_neighbors, random_index) |> list.first() {
        Ok(selected_neighbor) -> {
          let rumor_message = Rumor(state.rumor_content, state.id)
          process.send(selected_neighbor, rumor_message)
        }
        Error(_) -> Nil
      }
      // let neighbor_count = list.length(multiple_neighbors)
      // let selected_index = int.random(neighbor_count)

      // case get_neighbor_at_index(multiple_neighbors, selected_index) {
      //   Ok(neighbor) -> {
      //     let rumor_message = Rumor(state.rumor_content, state.id)
      //     process.send(neighbor, rumor_message)
      //   }
      //   Error(_) -> Nil
      // }
    }
    // multiple_neighbors -> {
    //   let neighbor_count = list.length(multiple_neighbors)
    //   let selected_index = state.rumor_count % neighbor_count

    //   case get_neighbor_at_index(multiple_neighbors, selected_index) {
    //     Ok(neighbor) -> {
    //       let rumor_message = Rumor(state.rumor_content, state.id)
    //       process.send(neighbor, rumor_message)
    //     }
    //     Error(_) -> Nil
    //   }
    // }
  }
}

fn get_neighbor_at_index(
  neighbors: List(process.Subject(GossipMessage)),
  index: Int,
) -> Result(process.Subject(GossipMessage), Nil) {
  case index >= 0 {
    True -> {
      list.drop(neighbors, index)
      |> list.first()
    }
    False -> Error(Nil)
  }
}

// TOPOLOGY BUILDING FUNCTIONS
pub fn build_neighbors(
  topology: Topology,
  num_nodes: Int,
) -> Dict(Int, List(Int)) {
  case topology {
    Full -> build_full_network(num_nodes)
    ThreeD -> build_3d_grid(num_nodes)
    Line -> build_line_topology(num_nodes)
    Imperfect3D -> build_imperfect_3d_grid(num_nodes)
  }
}

fn build_full_network(num_nodes: Int) -> Dict(Int, List(Int)) {
  let all_nodes = list.range(0, num_nodes - 1)
  list.fold(all_nodes, dict.new(), fn(acc, node) {
    let neighbors = list.filter(all_nodes, fn(n) { n != node })
    dict.insert(acc, node, neighbors)
  })
}

fn build_line_topology(num_nodes: Int) -> Dict(Int, List(Int)) {
  list.fold(list.range(0, num_nodes - 1), dict.new(), fn(acc, node) {
    let neighbors = case node {
      0 -> [1]
      n if n == num_nodes - 1 -> [n - 1]
      n -> [n - 1, n + 1]
    }
    dict.insert(acc, node, neighbors)
  })
}

fn build_3d_grid(num_nodes: Int) -> Dict(Int, List(Int)) {
  let side_length = calculate_cube_side(num_nodes)
  let positions = generate_3d_positions(side_length)

  list.fold(list.range(0, num_nodes - 1), dict.new(), fn(acc, node) {
    case get_element_at_index(positions, node) {
      Ok(pos) -> {
        let neighbors = get_3d_neighbors(pos, positions, side_length)
        dict.insert(acc, node, neighbors)
      }
      Error(_) -> acc
    }
  })
}

fn build_imperfect_3d_grid(num_nodes: Int) -> Dict(Int, List(Int)) {
  let grid_neighbors = build_3d_grid(num_nodes)

  list.fold(list.range(0, num_nodes - 1), grid_neighbors, fn(acc, node) {
    case dict.get(acc, node) {
      Ok(existing_neighbors) -> {
        let random_neighbor = case node {
          n if n < num_nodes - 1 -> n + 1
          _ -> 0
        }

        let new_neighbors = case
          list.contains(existing_neighbors, random_neighbor)
        {
          True -> existing_neighbors
          False -> [random_neighbor, ..existing_neighbors]
        }

        dict.insert(acc, node, new_neighbors)
      }
      Error(_) -> acc
    }
  })
}

fn calculate_cube_side(num_nodes: Int) -> Int {
  let float_side = float.power(int.to_float(num_nodes), 1.0 /. 3.0)
  case float_side {
    Ok(side) -> float.ceiling(side) |> float.round
    Error(_) -> int.max(1, num_nodes / 8)
  }
}

fn generate_3d_positions(side_length: Int) -> List(Position3D) {
  list.fold(list.range(0, side_length - 1), [], fn(acc_z, z) {
    list.fold(list.range(0, side_length - 1), acc_z, fn(acc_y, y) {
      list.fold(list.range(0, side_length - 1), acc_y, fn(acc_x, x) {
        [Position3D(x, y, z), ..acc_x]
      })
    })
  })
  |> list.reverse
}

fn get_3d_neighbors(
  pos: Position3D,
  all_positions: List(Position3D),
  side_length: Int,
) -> List(Int) {
  let Position3D(x, y, z) = pos

  let neighbor_deltas = [
    #(-1, 0, 0),
    #(1, 0, 0),
    #(0, -1, 0),
    #(0, 1, 0),
    #(0, 0, -1),
    #(0, 0, 1),
  ]

  list.filter_map(neighbor_deltas, fn(delta) {
    let #(dx, dy, dz) = delta
    let new_x = x + dx
    let new_y = y + dy
    let new_z = z + dz

    case
      new_x >= 0
      && new_x < side_length
      && new_y >= 0
      && new_y < side_length
      && new_z >= 0
      && new_z < side_length
    {
      True -> {
        let neighbor_pos = Position3D(new_x, new_y, new_z)
        find_position_index(neighbor_pos, all_positions, 0)
      }
      False -> Error(Nil)
    }
  })
}

fn find_position_index(
  target: Position3D,
  positions: List(Position3D),
  index: Int,
) -> Result(Int, Nil) {
  case positions {
    [] -> Error(Nil)
    [pos, ..rest] -> {
      case pos == target {
        True -> Ok(index)
        False -> find_position_index(target, rest, index + 1)
      }
    }
  }
}

fn get_element_at_index(list: List(a), index: Int) -> Result(a, Nil) {
  case index >= 0 {
    True -> {
      list.drop(list, index)
      |> list.first()
    }
    False -> Error(Nil)
  }
}

// ENHANCED SIMULATION RUNNER
pub fn run_gossip_simulation_with_monitor(
  num_nodes: Int,
  topology: Topology,
) -> Nil {
  io.println("🚀 Starting Gossip simulation with convergence monitoring...")
  io.println("   Nodes: " <> int.to_string(num_nodes))
  io.println("   Topology: " <> topology_to_string(topology))

  case start_convergence_monitor(num_nodes, topology) {
    Ok(monitor) -> {
      case create_gossip_actors_with_supervisor(num_nodes) {
        Ok(actors) -> {
          setup_supervisors(actors, monitor)
          let neighbor_map = build_neighbors(topology, num_nodes)
          setup_gossip_neighbors_enhanced(actors, neighbor_map)

          process.send(monitor, StartMonitoring)
          initiate_gossip_enhanced(actors, "I Heard A Rumor!")
          wait_for_convergence_with_monitor(monitor, 60_000)
          print_final_convergence_results(monitor)

          process.send(monitor, StopMonitoring)
          shutdown_gossip_actors_enhanced(actors)
        }
        Error(msg) -> io.println("❌ Failed to create actors: " <> msg)
      }
    }
    Error(_) -> io.println("❌ Failed to create convergence monitor")
  }
}

fn create_gossip_actors_with_supervisor(
  num_nodes: Int,
) -> Result(List(process.Subject(GossipMessage)), String) {
  list.range(0, num_nodes - 1)
  |> list.try_map(fn(id) {
    case start_gossip_actor_with_supervisor(id, num_nodes) {
      Ok(subject) -> Ok(subject)
      Error(_) -> Error("Failed to start actor " <> int.to_string(id))
    }
  })
}

fn setup_supervisors(
  actors: List(process.Subject(GossipMessage)),
  monitor: process.Subject(ConvergenceMessage),
) -> Nil {
  list.each(actors, fn(actor) { process.send(actor, SetSupervisor(monitor)) })
  io.println(
    "✅ Set supervisor for all "
    <> int.to_string(list.length(actors))
    <> " actors",
  )
}

fn setup_gossip_neighbors_enhanced(
  actors: List(process.Subject(GossipMessage)),
  neighbor_map: Dict(Int, List(Int)),
) -> Nil {
  list.index_map(actors, fn(actor, index) {
    case dict.get(neighbor_map, index) {
      Ok(neighbor_indices) -> {
        let neighbor_subjects =
          list.filter_map(neighbor_indices, fn(neighbor_index) {
            get_gossip_actor_at_index(actors, neighbor_index)
          })
        process.send(actor, SetNeighbors(neighbor_subjects))
      }
      Error(_) -> {
        io.println(
          "⚠️  Warning: No neighbors found for actor " <> int.to_string(index),
        )
      }
    }
  })
  Nil
}

fn get_gossip_actor_at_index(
  actors: List(process.Subject(GossipMessage)),
  index: Int,
) -> Result(process.Subject(GossipMessage), Nil) {
  case index >= 0 {
    True -> {
      list.drop(actors, index)
      |> list.first()
    }
    False -> Error(Nil)
  }
}

fn initiate_gossip_enhanced(
  actors: List(process.Subject(GossipMessage)),
  rumor: String,
) -> Nil {
  case actors {
    [] -> Nil
    [first_actor, ..] -> {
      io.println("📡 Initiating gossip with rumor: '" <> rumor <> "'")
      process.send(first_actor, Rumor(rumor, -1))
    }
  }
}

fn wait_for_convergence_with_monitor(
  monitor: process.Subject(ConvergenceMessage),
  timeout_ms: Int,
) -> Nil {
  let start_time = get_current_time_ms()
  monitor_convergence_loop(monitor, start_time, timeout_ms, 2000)
}

fn monitor_convergence_loop(
  monitor: process.Subject(ConvergenceMessage),
  start_time: Int,
  timeout_ms: Int,
  check_interval: Int,
) -> Nil {
  let current_time = get_current_time_ms()

  case current_time - start_time > timeout_ms {
    True -> {
      io.println(
        "⏰ TIMEOUT: Convergence monitoring stopped after "
        <> int.to_string(timeout_ms)
        <> "ms",
      )
      process.send(monitor, CheckConvergenceStatus)
    }
    False -> {
      // Ask the monitor for the current convergence result
      let result = process.call(monitor, 1000, GetConvergenceResult)
      let ConvergenceResult(converged: converged, ..) = result

      case converged {
        True -> {
          io.println("✅ Convergence achieved. Exiting run loop.")
          // Return without recursion; caller will perform cleanup and exit
          Nil
        }
        False -> {
          process.send(monitor, CheckConvergenceStatus)
          process.sleep(check_interval)
          monitor_convergence_loop(
            monitor,
            start_time,
            timeout_ms,
            check_interval,
          )
        }
      }
    }
  }
}

fn print_final_convergence_results(
  monitor: process.Subject(ConvergenceMessage),
) -> Nil {
  io.println("📋 FINAL CONVERGENCE RESULTS:")
  let result = process.call(monitor, 1000, GetConvergenceResult)
  let ConvergenceResult(
    converged: c,
    time_to_convergence: t,
    coverage_percentage: cov,
    nodes_with_rumor: nwr,
    total_nodes: tn,
    terminated_nodes: tnz,
  ) = result

  io.println("   Converged: " <> bool_to_string(c))
  io.println(
    "   Nodes with rumor: "
    <> int.to_string(nwr)
    <> "/"
    <> int.to_string(tn)
    <> " ("
    <> float.to_string(cov *. 100.0)
    <> "%)",
  )
  io.println(
    "   Terminated nodes: " <> int.to_string(tnz) <> "/" <> int.to_string(tn),
  )
  case t {
    Some(ms) -> io.println("   Convergence time: " <> int.to_string(ms) <> "ms")
    None -> io.println("   Convergence time: Unknown")
  }
}

fn shutdown_gossip_actors_enhanced(
  actors: List(process.Subject(GossipMessage)),
) -> Nil {
  io.println("🔄 Shutting down all gossip actors...")
  list.each(actors, fn(actor) { process.send(actor, Shutdown) })
}

// UTILITY FUNCTIONS
fn get_current_time_ms() -> Int {
  // Placeholder - implement with proper Gleam time functions
  let ts = timestamp.system_time()
  let #(seconds, nanoseconds) = timestamp.to_unix_seconds_and_nanoseconds(ts)

  // Convert to milliseconds
  seconds * 1000 + nanoseconds / 1_000_000
}

fn bool_to_string(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}

fn topology_to_string(topology: Topology) -> String {
  case topology {
    Full -> "Full Network"
    ThreeD -> "3D Grid"
    Line -> "Line"
    Imperfect3D -> "Imperfect 3D Grid"
  }
}

fn algorithm_to_string(algorithm: Algorithm) -> String {
  case algorithm {
    Gossip -> "Gossip"
    PushSum -> "Push-Sum"
  }
}

// MAIN ENTRY POINT
pub fn main() {
  case parse_command_args() {
    Ok(#(num_nodes, topology, algorithm)) -> {
      io.println("Starting Enhanced Gossip Protocol Simulation")
      io.println("Nodes: " <> int.to_string(num_nodes))
      io.println("Topology: " <> topology_to_string(topology))
      io.println("Algorithm: " <> algorithm_to_string(algorithm))

      case algorithm {
        Gossip -> run_gossip_simulation_with_monitor(num_nodes, topology)
        PushSum -> run_pushsum_simulation(num_nodes, topology)
      }
    }
    Error(msg) -> {
      io.println("Error: " <> msg)
      io.println("Usage: project2 <numNodes> <topology> <algorithm>")
      io.println("Topology: full, 3D, line, imp3D")
      io.println("Algorithm: gossip, push-sum")
    }
  }
}

fn parse_command_args() -> Result(#(Int, Topology, Algorithm), String) {
  case envoy.get("GLEAM_MAIN_ARGS") {
    Ok(args_str) -> {
      let args = string.split(args_str, " ")
      case args {
        [num_str, topology_str, algorithm_str] -> {
          case int.parse(num_str) {
            Ok(num_nodes) -> {
              case parse_topology(topology_str) {
                Ok(topology) -> {
                  case parse_algorithm(algorithm_str) {
                    Ok(algorithm) -> Ok(#(num_nodes, topology, algorithm))
                    Error(e) -> Error(e)
                  }
                }
                Error(e) -> Error(e)
              }
            }
            Error(_) -> Error("Invalid number of nodes: " <> num_str)
          }
        }
        _ -> Error("Expected 3 arguments: <numNodes> <topology> <algorithm>")
      }
    }
    Error(_) -> {
      io.println("No command arguments found, using defaults for testing")
      Ok(#(1000, Full, Gossip))
      //Ok(#(1000, ThreeD, Gossip))
      //Ok(#(100, Line, Gossip))
      //Ok(#(1000, Imperfect3D, Gossip))
    }
  }
}

fn parse_topology(topology_str: String) -> Result(Topology, String) {
  case string.lowercase(topology_str) {
    "full" -> Ok(Full)
    "3d" -> Ok(ThreeD)
    "line" -> Ok(Line)
    "imp3d" -> Ok(Imperfect3D)
    _ -> Error("Invalid topology: " <> topology_str)
  }
}

fn parse_algorithm(algorithm_str: String) -> Result(Algorithm, String) {
  case string.lowercase(algorithm_str) {
    "gossip" -> Ok(Gossip)
    "push-sum" -> Ok(PushSum)
    _ -> Error("Invalid algorithm: " <> algorithm_str)
  }
}

fn run_pushsum_simulation(num_nodes: Int, topology: Topology) -> Nil {
  io.println("Running Push-Sum simulation...")
  // Implementation will go here
  Nil
}
