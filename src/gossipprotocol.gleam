// project2.gleam - Enhanced Gossip Protocol with Convergence Monitoring
import argv
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

// =============================================================================
// CORE TYPES AND ENUMS
// =============================================================================

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

pub type Position3D {
  Position3D(x: Int, y: Int, z: Int)
}

// =============================================================================
// GOSSIP PROTOCOL TYPES
// =============================================================================

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

// =============================================================================
// GOSSIP CONVERGENCE MONITOR TYPES
// =============================================================================

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

// =============================================================================
// PUSH-SUM PROTOCOL TYPES
// =============================================================================

pub type PushSumMessage {
  PushSumPair(s: Float, w: Float, sender_id: Int)
  SetPushSumNeighbors(neighbors: List(process.Subject(PushSumMessage)))
  SetPushSumSupervisor(supervisor: process.Subject(PushSumConvergenceMessage))
  PushSumShutdown
  GetPushSumStatus
}

pub type PushSumState {
  PushSumState(
    id: Int,
    neighbors: List(process.Subject(PushSumMessage)),
    s: Float,
    w: Float,
    prev_ratios: List(Float),
    total_nodes: Int,
    terminated: Bool,
    supervisor: option.Option(process.Subject(PushSumConvergenceMessage)),
    round_count: Int,
  )
}

// =============================================================================
// PUSH-SUM CONVERGENCE MONITOR TYPES
// =============================================================================

pub type PushSumConvergenceMessage {
  NodeConverged(node_id: Int, final_estimate: Float)
  CheckPushSumConvergenceStatus
  GetPushSumConvergenceResult(
    reply_to: process.Subject(PushSumConvergenceResult),
  )
  StartPushSumMonitoring
  StopPushSumMonitoring
}

pub type PushSumConvergenceState {
  PushSumConvergenceState(
    total_nodes: Int,
    converged_nodes: Set(Int),
    node_estimates: Dict(Int, Float),
    convergence_achieved: Bool,
    convergence_time: option.Option(Int),
    start_time: Int,
    monitoring_active: Bool,
    expected_average: Float,
  )
}

pub type PushSumConvergenceResult {
  PushSumConvergenceResult(
    converged: Bool,
    time_to_convergence: option.Option(Int),
    convergence_percentage: Float,
    converged_nodes: Int,
    total_nodes: Int,
    average_estimate: Float,
    expected_average: Float,
  )
}

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

fn get_current_time_ms() -> Int {
  let ts = timestamp.system_time()
  let #(seconds, nanoseconds) = timestamp.to_unix_seconds_and_nanoseconds(ts)
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

fn get_element_at_index(list: List(a), index: Int) -> Result(a, Nil) {
  case index >= 0 {
    True -> {
      list.drop(list, index)
      |> list.first()
    }
    False -> Error(Nil)
  }
}

fn get_convergence_threshold(topology: Topology) -> Float {
  case topology {
    Full -> 0.2
    Imperfect3D -> 0.91
    ThreeD -> 0.91
    Line -> 0.8
  }
}

fn calculate_expected_average(total_nodes: Int) -> Float {
  int.to_float(total_nodes - 1) /. 2.0
}

// =============================================================================
// TOPOLOGY BUILDING FUNCTIONS
// =============================================================================

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

// =============================================================================
// GOSSIP CONVERGENCE MONITOR IMPLEMENTATION
// =============================================================================

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
            "Node " <> int.to_string(node_id) <> " heard rumor for first time",
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

              io.println("CONVERGENCE ACHIEVED!")
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
          io.println(
            "Warning: Received NodeFirstHeardRumor but monitoring not active",
          )
          actor.continue(state)
        }
      }
    }

    NodeTerminated(node_id) -> {
      let updated_terminated = set.insert(state.terminated_nodes, node_id)
      let terminated_count = set.size(updated_terminated)

      io.println("Node " <> int.to_string(node_id) <> " terminated")
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

      io.println("CONVERGENCE STATUS:")
      io.println(
        "   Nodes with rumor: "
        <> string.inspect(set.to_list(state.nodes_with_rumor))
        <> "/"
        <> int.to_string(state.total_nodes)
        <> " ("
        <> float.to_string(coverage *. 100.0)
        <> "%)",
      )
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

// =============================================================================
// GOSSIP ACTOR IMPLEMENTATION
// =============================================================================

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
      let neighbor_count = list.length(new_neighbors)
      // io.println(
      //   "Node "
      //   <> int.to_string(state.id)
      //   <> " received "
      //   <> int.to_string(neighbor_count)
      //   <> " neighbors",
      // )
      let updated_state = GossipState(..state, neighbors: new_neighbors)
      actor.continue(updated_state)
    }

    SetSupervisor(supervisor) -> {
      // io.println(
      //   "Node " <> int.to_string(state.id) <> " received supervisor reference",
      // )
      let updated_state = GossipState(..state, supervisor: Some(supervisor))
      actor.continue(updated_state)
    }

    Rumor(content, sender_id) -> {
      case state.terminated {
        True -> {
          io.println(
            "Node "
            <> int.to_string(state.id)
            <> " (TERMINATED) received rumor from Node "
            <> int.to_string(sender_id)
            <> " but ignoring it",
          )
          actor.continue(state)
        }
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

          case is_first_time {
            True -> {
              io.println(
                "Node "
                <> int.to_string(state.id)
                <> " heard rumor for FIRST time from Node "
                <> int.to_string(sender_id)
                <> " - '"
                <> content
                <> "'",
              )
              case state.supervisor {
                Some(supervisor) ->
                  process.send(supervisor, NodeFirstHeardRumor(state.id))
                None -> Nil
              }
            }
            False -> {
              io.println(
                "Node "
                <> int.to_string(state.id)
                <> " heard rumor again from Node "
                <> int.to_string(sender_id)
                <> " (count now: "
                <> int.to_string(new_count)
                <> ")",
              )
            }
          }

          case new_count >= 30 {
            True -> {
              io.println(
                "Node "
                <> int.to_string(state.id)
                <> " TERMINATING after hearing rumor "
                <> int.to_string(new_count)
                <> " times - no more spreading",
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
              io.println(
                "Node "
                <> int.to_string(state.id)
                <> " will now spread rumor (heard "
                <> int.to_string(new_count)
                <> " times so far)",
              )
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
    [] -> {
      io.println(
        "Node "
        <> int.to_string(state.id)
        <> " has no neighbors to spread rumor to",
      )
      Nil
    }
    [single_neighbor] -> {
      let rumor_message = Rumor(state.rumor_content, state.id)
      io.println(
        "Node "
        <> int.to_string(state.id)
        <> " spreading rumor to its only neighbor (rumor count: "
        <> int.to_string(state.rumor_count)
        <> ")",
      )
      process.send(single_neighbor, rumor_message)
    }
    multiple_neighbors -> {
      let neighbor_count = list.length(multiple_neighbors)
      let random_index = int.random(neighbor_count)
      case get_neighbor_at_index(multiple_neighbors, random_index) {
        Ok(selected_neighbor) -> {
          let rumor_message = Rumor(state.rumor_content, state.id)
          io.println(
            "Node "
            <> int.to_string(state.id)
            <> " spreading rumor to random neighbor (index "
            <> int.to_string(random_index)
            <> " of "
            <> int.to_string(neighbor_count - 1)
            <> ") - rumor count: "
            <> int.to_string(state.rumor_count),
          )
          process.send(selected_neighbor, rumor_message)
        }
        Error(_) -> {
          case list.first(multiple_neighbors) {
            Ok(first_neighbor) -> {
              let rumor_message = Rumor(state.rumor_content, state.id)
              io.println(
                "Node "
                <> int.to_string(state.id)
                <> " spreading rumor to first neighbor (fallback) - rumor count: "
                <> int.to_string(state.rumor_count),
              )
              process.send(first_neighbor, rumor_message)
            }
            Error(_) -> {
              io.println(
                "Node "
                <> int.to_string(state.id)
                <> " failed to find any valid neighbor",
              )
              Nil
            }
          }
        }
      }
    }
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

// =============================================================================
// PUSH-SUM CONVERGENCE MONITOR IMPLEMENTATION
// =============================================================================

pub fn start_pushsum_convergence_monitor(
  total_nodes: Int,
) -> Result(process.Subject(PushSumConvergenceMessage), actor.StartError) {
  let expected_average = calculate_expected_average(total_nodes)
  let initial_state =
    PushSumConvergenceState(
      total_nodes: total_nodes,
      converged_nodes: set.new(),
      node_estimates: dict.new(),
      convergence_achieved: False,
      convergence_time: None,
      start_time: 0,
      monitoring_active: False,
      expected_average: expected_average,
    )

  case
    actor.new(initial_state)
    |> actor.on_message(handle_pushsum_convergence_message)
    |> actor.start()
  {
    Ok(started) -> Ok(started.data)
    Error(e) -> Error(e)
  }
}

pub fn handle_pushsum_convergence_message(
  state: PushSumConvergenceState,
  message: PushSumConvergenceMessage,
) -> actor.Next(PushSumConvergenceState, PushSumConvergenceMessage) {
  case message {
    StartPushSumMonitoring -> {
      io.println("Push-Sum Monitor: Starting to monitor convergence")
      let start_time = get_current_time_ms()
      let updated_state =
        PushSumConvergenceState(
          ..state,
          monitoring_active: True,
          start_time: start_time,
        )
      actor.continue(updated_state)
    }
    NodeConverged(node_id, final_estimate) -> {
      case state.monitoring_active {
        True -> {
          let updated_nodes = set.insert(state.converged_nodes, node_id)
          let updated_estimates =
            dict.insert(state.node_estimates, node_id, final_estimate)
          let convergence_percentage =
            int.to_float(set.size(updated_nodes))
            /. int.to_float(state.total_nodes)

          io.println(
            "Node "
            <> int.to_string(node_id)
            <> " converged with estimate: "
            <> float.to_string(final_estimate),
          )
          io.println(
            "   Expected average: " <> float.to_string(state.expected_average),
          )
          io.println(
            "   Error: "
            <> float.to_string(float.absolute_value(
              final_estimate -. state.expected_average,
            )),
          )
          io.println(
            "   Convergence: "
            <> int.to_string(set.size(updated_nodes))
            <> "/"
            <> int.to_string(state.total_nodes)
            <> " = "
            <> float.to_string(convergence_percentage *. 100.0)
            <> "%",
          )

          case convergence_percentage >=. 0.9 && !state.convergence_achieved {
            True -> {
              let current_time = get_current_time_ms()
              let elapsed = current_time - state.start_time

              io.println("PUSH-SUM CONVERGENCE ACHIEVED!")
              io.println(
                "   Time to convergence: " <> int.to_string(elapsed) <> "ms",
              )
              io.println(
                "   Final convergence time: " <> int.to_string(elapsed) <> "ms",
              )
              io.println(
                "   Converged nodes: "
                <> int.to_string(set.size(updated_nodes))
                <> "/"
                <> int.to_string(state.total_nodes),
              )

              let converged_state =
                PushSumConvergenceState(
                  ..state,
                  converged_nodes: updated_nodes,
                  node_estimates: updated_estimates,
                  convergence_achieved: True,
                  convergence_time: Some(elapsed),
                )
              actor.continue(converged_state)
            }
            False -> {
              let updated_state =
                PushSumConvergenceState(
                  ..state,
                  converged_nodes: updated_nodes,
                  node_estimates: updated_estimates,
                )
              actor.continue(updated_state)
            }
          }
        }
        False -> {
          io.println(
            "Warning: Received NodeConverged but monitoring not active",
          )
          actor.continue(state)
        }
      }
    }

    // NodeConverged(node_id, final_estimate) -> {
    //   case state.monitoring_active {
    //     True -> {
    //       let updated_nodes = set.insert(state.converged_nodes, node_id)
    //       let updated_estimates =
    //         dict.insert(state.node_estimates, node_id, final_estimate)
    //       let convergence_percentage =
    //         int.to_float(set.size(updated_nodes))
    //         /. int.to_float(state.total_nodes)
    //       io.println(
    //         "Node "
    //         <> int.to_string(node_id)
    //         <> " converged with estimate: "
    //         <> float.to_string(final_estimate),
    //       )
    //       io.println(
    //         "   Expected average: " <> float.to_string(state.expected_average),
    //       )
    //       io.println(
    //         "   Error: "
    //         <> float.to_string(float.absolute_value(
    //           final_estimate -. state.expected_average,
    //         )),
    //       )
    //       io.println(
    //         "   Convergence: "
    //         <> int.to_string(set.size(updated_nodes))
    //         <> "/"
    //         <> int.to_string(state.total_nodes)
    //         <> " = "
    //         <> float.to_string(convergence_percentage *. 100.0)
    //         <> "%",
    //       )
    //       case convergence_percentage >=. 0.9 && !state.convergence_achieved {
    //         True -> {
    //           let current_time = get_current_time_ms()
    //           let elapsed = current_time - state.start_time
    //           io.println("PUSH-SUM CONVERGENCE ACHIEVED!")
    //           io.println(
    //             "   Time to convergence: " <> int.to_string(elapsed) <> "ms",
    //           )
    //           io.println(
    //             "   Converged nodes: "
    //             <> int.to_string(set.size(updated_nodes))
    //             <> "/"
    //             <> int.to_string(state.total_nodes),
    //           )
    //           let converged_state =
    //             PushSumConvergenceState(
    //               ..state,
    //               converged_nodes: updated_nodes,
    //               node_estimates: updated_estimates,
    //               convergence_achieved: True,
    //               convergence_time: Some(elapsed),
    //             )
    //           actor.continue(converged_state)
    //         }
    //         False -> {
    //           let updated_state =
    //             PushSumConvergenceState(
    //               ..state,
    //               converged_nodes: updated_nodes,
    //               node_estimates: updated_estimates,
    //             )
    //           actor.continue(updated_state)
    //         }
    //       }
    //     }
    //     False -> {
    //       io.println(
    //         "Warning: Received NodeConverged but monitoring not active",
    //       )
    //       actor.continue(state)
    //     }
    //   }
    // }
    CheckPushSumConvergenceStatus -> {
      let convergence_percentage =
        int.to_float(set.size(state.converged_nodes))
        /. int.to_float(state.total_nodes)

      io.println("PUSH-SUM CONVERGENCE STATUS:")
      io.println(
        "   Converged nodes: "
        <> int.to_string(set.size(state.converged_nodes))
        <> "/"
        <> int.to_string(state.total_nodes)
        <> " ("
        <> float.to_string(convergence_percentage *. 100.0)
        <> "%)",
      )
      io.println(
        "   Expected average: " <> float.to_string(state.expected_average),
      )
      io.println("   Converged: " <> bool_to_string(state.convergence_achieved))

      dict.each(state.node_estimates, fn(node_id, estimate) {
        let error = float.absolute_value(estimate -. state.expected_average)
        io.println(
          "   Node "
          <> int.to_string(node_id)
          <> ": "
          <> float.to_string(estimate)
          <> " (error: "
          <> float.to_string(error)
          <> ")",
        )
      })

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

    GetPushSumConvergenceResult(reply_to) -> {
      let convergence_percentage =
        int.to_float(set.size(state.converged_nodes))
        /. int.to_float(state.total_nodes)

      let average_estimate = case set.size(state.converged_nodes) {
        0 -> 0.0
        n -> {
          let sum =
            dict.fold(state.node_estimates, 0.0, fn(acc, _, estimate) {
              acc +. estimate
            })
          sum /. int.to_float(n)
        }
      }

      let result =
        PushSumConvergenceResult(
          converged: state.convergence_achieved,
          time_to_convergence: state.convergence_time,
          convergence_percentage: convergence_percentage,
          converged_nodes: set.size(state.converged_nodes),
          total_nodes: state.total_nodes,
          average_estimate: average_estimate,
          expected_average: state.expected_average,
        )

      process.send(reply_to, result)
      actor.continue(state)
    }

    StopPushSumMonitoring -> {
      let final_state =
        PushSumConvergenceState(..state, monitoring_active: False)
      actor.continue(final_state)
    }
  }
}

// =============================================================================
// PUSH-SUM ACTOR IMPLEMENTATION
// =============================================================================

pub fn start_pushsum_actor_with_supervisor(
  id: Int,
  total_nodes: Int,
) -> Result(process.Subject(PushSumMessage), actor.StartError) {
  let initial_state =
    PushSumState(
      id: id,
      neighbors: [],
      s: int.to_float(id),
      w: 1.0,
      prev_ratios: [],
      total_nodes: total_nodes,
      terminated: False,
      supervisor: None,
      round_count: 0,
    )

  case
    actor.new(initial_state)
    |> actor.on_message(handle_pushsum_message_with_supervisor)
    |> actor.start()
  {
    Ok(started) -> Ok(started.data)
    Error(e) -> Error(e)
  }
}

pub fn handle_pushsum_message_with_supervisor(
  state: PushSumState,
  message: PushSumMessage,
) -> actor.Next(PushSumState, PushSumMessage) {
  case message {
    SetPushSumNeighbors(new_neighbors) -> {
      let updated_state = PushSumState(..state, neighbors: new_neighbors)
      actor.continue(updated_state)
    }

    SetPushSumSupervisor(supervisor) -> {
      io.println(
        "Push-Sum Node "
        <> int.to_string(state.id)
        <> " received supervisor reference",
      )
      let updated_state = PushSumState(..state, supervisor: Some(supervisor))
      actor.continue(updated_state)
    }

    PushSumPair(received_s, received_w, sender_id) -> {
      case state.terminated {
        True -> {
          let new_s = state.s +. received_s
          let new_w = state.w +. received_w

          // io.println(
          //   "Node "
          //   <> int.to_string(state.id)
          //   <> " (CONVERGED) received from Node "
          //   <> int.to_string(sender_id)
          //   <> " - s="
          //   <> float.to_string(received_s)
          //   <> ", w="
          //   <> float.to_string(received_w),
          // )

          let updated_state = PushSumState(..state, s: new_s, w: new_w)
          let final_state = send_pushsum_to_neighbor_and_update(updated_state)
          actor.continue(final_state)
        }
        False -> {
          let new_s = state.s +. received_s
          let new_w = state.w +. received_w
          let current_ratio = new_s /. new_w
          let new_round_count = state.round_count + 1

          // io.println(
          //   "Node "
          //   <> int.to_string(state.id)
          //   <> " received from Node "
          //   <> int.to_string(sender_id)
          //   <> " - s="
          //   <> float.to_string(received_s)
          //   <> ", w="
          //   <> float.to_string(received_w)
          //   <> " | New ratio: "
          //   <> float.to_string(current_ratio),
          // )

          let updated_ratios = [current_ratio, ..state.prev_ratios]
          let ratios_to_keep = list.take(updated_ratios, 3)

          let intermediate_state =
            PushSumState(
              ..state,
              s: new_s,
              w: new_w,
              prev_ratios: ratios_to_keep,
              round_count: new_round_count,
            )

          let final_state =
            send_pushsum_to_neighbor_and_update(intermediate_state)

          case check_pushsum_convergence(ratios_to_keep) {
            True -> {
              // io.println(
              //   "Node "
              //   <> int.to_string(state.id)
              //   <> " converged! Final estimate: "
              //   <> float.to_string(current_ratio)
              //   <> " after "
              //   <> int.to_string(new_round_count)
              //   <> " rounds",
              // )

              case state.supervisor {
                Some(supervisor) ->
                  process.send(
                    supervisor,
                    NodeConverged(state.id, current_ratio),
                  )
                None -> Nil
              }

              let terminated_state =
                PushSumState(..final_state, terminated: True)
              actor.continue(terminated_state)
            }
            False -> {
              actor.continue(final_state)
            }
          }
        }
      }
    }

    PushSumShutdown -> {
      io.println(
        "Push-Sum Node " <> int.to_string(state.id) <> " shutting down",
      )
      actor.stop()
    }

    GetPushSumStatus -> {
      let current_ratio = case state.w >. 0.0 {
        True -> state.s /. state.w
        False -> 0.0
      }
      io.println(
        "Push-Sum Node "
        <> int.to_string(state.id)
        <> " - s="
        <> float.to_string(state.s)
        <> ", w="
        <> float.to_string(state.w)
        <> ", ratio="
        <> float.to_string(current_ratio)
        <> ", rounds="
        <> int.to_string(state.round_count)
        <> ", terminated="
        <> bool_to_string(state.terminated),
      )
      actor.continue(state)
    }
  }
}

fn send_pushsum_to_neighbor_and_update(state: PushSumState) -> PushSumState {
  case state.neighbors {
    [] -> state
    neighbors -> {
      let neighbor_count = list.length(neighbors)
      let random_index = int.random(neighbor_count)
      case get_pushsum_neighbor_at_index(neighbors, random_index) {
        Ok(selected_neighbor) -> {
          let half_s = state.s /. 2.0
          let half_w = state.w /. 2.0
          let message = PushSumPair(half_s, half_w, state.id)
          process.send(selected_neighbor, message)

          // io.println(
          //   "Node "
          //   <> int.to_string(state.id)
          //   <> " sent half: s="
          //   <> float.to_string(half_s)
          //   <> ", w="
          //   <> float.to_string(half_w)
          //   <> " (keeping s="
          //   <> float.to_string(half_s)
          //   <> ", w="
          //   <> float.to_string(half_w)
          //   <> ")",
          // )

          PushSumState(..state, s: half_s, w: half_w)
        }
        Error(_) -> {
          case list.first(neighbors) {
            Ok(first_neighbor) -> {
              let half_s = state.s /. 2.0
              let half_w = state.w /. 2.0
              let message = PushSumPair(half_s, half_w, state.id)
              process.send(first_neighbor, message)
              PushSumState(..state, s: half_s, w: half_w)
            }
            Error(_) -> state
          }
        }
      }
    }
  }
}

fn check_pushsum_convergence(ratios: List(Float)) -> Bool {
  case ratios {
    [r1, r2, r3, ..] -> {
      let diff1 = float.absolute_value(r1 -. r2)
      let diff2 = float.absolute_value(r2 -. r3)
      let threshold = 0.0000000001
      let result = diff1 <=. threshold && diff2 <=. threshold

      // io.println(
      //   "   Convergence check: diff1="
      //   <> float.to_string(diff1)
      //   <> ", diff2="
      //   <> float.to_string(diff2)
      //   <> ", threshold="
      //   <> float.to_string(threshold)
      //   <> " -> "
      //   <> bool_to_string(result),
      // )

      result
    }
    _ -> False
  }
}

fn get_pushsum_neighbor_at_index(
  neighbors: List(process.Subject(PushSumMessage)),
  index: Int,
) -> Result(process.Subject(PushSumMessage), Nil) {
  case index >= 0 {
    True -> {
      list.drop(neighbors, index)
      |> list.first()
    }
    False -> Error(Nil)
  }
}

// =============================================================================
// GOSSIP SIMULATION RUNNER
// =============================================================================

pub fn run_gossip_simulation_with_monitor(
  num_nodes: Int,
  topology: Topology,
) -> Nil {
  io.println("Starting Gossip simulation with convergence monitoring...")
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
        Error(msg) -> io.println("Failed to create actors: " <> msg)
      }
    }
    Error(_) -> io.println("Failed to create convergence monitor")
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
    "Set supervisor for all " <> int.to_string(list.length(actors)) <> " actors",
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
          "Warning: No neighbors found for actor " <> int.to_string(index),
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
      io.println("Initiating gossip with rumor: '" <> rumor <> "'")
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
        "TIMEOUT: Convergence monitoring stopped after "
        <> int.to_string(timeout_ms)
        <> "ms",
      )
      process.send(monitor, CheckConvergenceStatus)
    }
    False -> {
      let result = process.call(monitor, 1000, GetConvergenceResult)
      let ConvergenceResult(converged: converged, ..) = result

      case converged {
        True -> {
          io.println("Convergence achieved. Exiting run loop.")
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
  io.println("FINAL CONVERGENCE RESULTS:")
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
  io.println("Shutting down all gossip actors...")
  list.each(actors, fn(actor) { process.send(actor, Shutdown) })
}

// =============================================================================
// PUSH-SUM SIMULATION RUNNER
// =============================================================================

pub fn run_pushsum_simulation_with_monitor(
  num_nodes: Int,
  topology: Topology,
) -> Nil {
  io.println("Starting Push-Sum simulation with convergence monitoring...")
  io.println("   Nodes: " <> int.to_string(num_nodes))
  io.println("   Topology: " <> topology_to_string(topology))
  io.println(
    "   Expected average: "
    <> float.to_string(calculate_expected_average(num_nodes)),
  )

  case start_pushsum_convergence_monitor(num_nodes) {
    Ok(monitor) -> {
      case create_pushsum_actors_with_supervisor(num_nodes) {
        Ok(actors) -> {
          setup_pushsum_supervisors(actors, monitor)
          let neighbor_map = build_neighbors(topology, num_nodes)
          setup_pushsum_neighbors(actors, neighbor_map)

          process.send(monitor, StartPushSumMonitoring)
          initiate_pushsum(actors)
          wait_for_pushsum_convergence_with_monitor(monitor, 120_000)
          print_final_pushsum_convergence_results(monitor)

          process.send(monitor, StopPushSumMonitoring)
          shutdown_pushsum_actors(actors)
        }
        Error(msg) -> io.println("Failed to create Push-Sum actors: " <> msg)
      }
    }
    Error(_) -> io.println("Failed to create Push-Sum convergence monitor")
  }
}

fn create_pushsum_actors_with_supervisor(
  num_nodes: Int,
) -> Result(List(process.Subject(PushSumMessage)), String) {
  list.range(0, num_nodes - 1)
  |> list.try_map(fn(id) {
    case start_pushsum_actor_with_supervisor(id, num_nodes) {
      Ok(subject) -> Ok(subject)
      Error(_) -> Error("Failed to start Push-Sum actor " <> int.to_string(id))
    }
  })
}

fn setup_pushsum_supervisors(
  actors: List(process.Subject(PushSumMessage)),
  monitor: process.Subject(PushSumConvergenceMessage),
) -> Nil {
  list.each(actors, fn(actor) {
    process.send(actor, SetPushSumSupervisor(monitor))
  })
  io.println(
    "Set Push-Sum supervisor for all "
    <> int.to_string(list.length(actors))
    <> " actors",
  )
}

fn setup_pushsum_neighbors(
  actors: List(process.Subject(PushSumMessage)),
  neighbor_map: Dict(Int, List(Int)),
) -> Nil {
  list.index_map(actors, fn(actor, index) {
    case dict.get(neighbor_map, index) {
      Ok(neighbor_indices) -> {
        let neighbor_subjects =
          list.filter_map(neighbor_indices, fn(neighbor_index) {
            get_pushsum_actor_at_index(actors, neighbor_index)
          })
        process.send(actor, SetPushSumNeighbors(neighbor_subjects))
      }
      Error(_) -> {
        io.println(
          "Warning: No neighbors found for Push-Sum actor "
          <> int.to_string(index),
        )
      }
    }
  })
  Nil
}

fn get_pushsum_actor_at_index(
  actors: List(process.Subject(PushSumMessage)),
  index: Int,
) -> Result(process.Subject(PushSumMessage), Nil) {
  case index >= 0 {
    True -> {
      list.drop(actors, index)
      |> list.first()
    }
    False -> Error(Nil)
  }
}

fn initiate_pushsum(actors: List(process.Subject(PushSumMessage))) -> Nil {
  case actors {
    [] -> Nil
    [first_actor, ..] -> {
      io.println("Initiating Push-Sum protocol")
      process.send(first_actor, PushSumPair(0.0, 0.0, -1))
    }
  }
}

fn wait_for_pushsum_convergence_with_monitor(
  monitor: process.Subject(PushSumConvergenceMessage),
  timeout_ms: Int,
) -> Nil {
  let start_time = get_current_time_ms()
  monitor_pushsum_convergence_loop(monitor, start_time, timeout_ms, 3000)
}

fn monitor_pushsum_convergence_loop(
  monitor: process.Subject(PushSumConvergenceMessage),
  start_time: Int,
  timeout_ms: Int,
  check_interval: Int,
) -> Nil {
  let current_time = get_current_time_ms()

  case current_time - start_time > timeout_ms {
    True -> {
      io.println(
        "TIMEOUT: Push-Sum convergence monitoring stopped after "
        <> int.to_string(timeout_ms)
        <> "ms",
      )
      process.send(monitor, CheckPushSumConvergenceStatus)
    }
    False -> {
      let result = process.call(monitor, 1000, GetPushSumConvergenceResult)
      let PushSumConvergenceResult(converged: converged, ..) = result

      case converged {
        True -> {
          io.println("Push-Sum convergence achieved. Exiting run loop.")
          Nil
        }
        False -> {
          process.send(monitor, CheckPushSumConvergenceStatus)
          process.sleep(check_interval)
          monitor_pushsum_convergence_loop(
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

fn print_final_pushsum_convergence_results(
  monitor: process.Subject(PushSumConvergenceMessage),
) -> Nil {
  io.println("FINAL PUSH-SUM CONVERGENCE RESULTS:")
  let result = process.call(monitor, 1000, GetPushSumConvergenceResult)
  let PushSumConvergenceResult(
    converged: c,
    time_to_convergence: t,
    convergence_percentage: cov,
    converged_nodes: cn,
    total_nodes: tn,
    average_estimate: avg_est,
    expected_average: exp_avg,
  ) = result

  io.println("   Converged: " <> bool_to_string(c))
  io.println(
    "   TOTAL CONVERGED NODES: "
    <> int.to_string(cn)
    <> " out of "
    <> int.to_string(tn),
  )
  io.println(
    "   Convergence percentage: " <> float.to_string(cov *. 100.0) <> "%",
  )
  io.println("   Expected average: " <> float.to_string(exp_avg))
  io.println("   Actual average estimate: " <> float.to_string(avg_est))
  io.println(
    "   Final error: "
    <> float.to_string(float.absolute_value(avg_est -. exp_avg)),
  )
  case t {
    Some(ms) -> io.println("   Convergence time: " <> int.to_string(ms) <> "ms")
    None -> io.println("   Convergence time: Unknown")
  }
}

fn shutdown_pushsum_actors(actors: List(process.Subject(PushSumMessage))) -> Nil {
  io.println("Shutting down all Push-Sum actors...")
  list.each(actors, fn(actor) { process.send(actor, PushSumShutdown) })
}

// =============================================================================
// COMMAND LINE PARSING
// =============================================================================

fn parse_command_args() -> Result(#(Int, Topology, Algorithm), String) {
  let args = argv.load().arguments

  case args {
    [num_str, topology_str, algorithm_str] -> {
      case int.parse(num_str) {
        Ok(num_nodes) -> {
          case parse_topology(topology_str) {
            Ok(topology) -> {
              case parse_algorithm(algorithm_str) {
                Ok(algorithm) -> {
                  Ok(#(num_nodes, topology, algorithm))
                }
                Error(e) -> Error(e)
              }
            }
            Error(e) -> Error(e)
          }
        }
        Error(_) -> Error("Invalid number of nodes: " <> num_str)
      }
    }
    _ -> {
      io.println("No command arguments found, using defaults for testing")
      Ok(#(27, Imperfect3D, Gossip))
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

// =============================================================================
// MAIN ENTRY POINT
// =============================================================================

pub fn main() {
  case parse_command_args() {
    Ok(#(num_nodes, topology, algorithm)) -> {
      io.println("Starting Enhanced Gossip Protocol Simulation")
      io.println("Nodes: " <> int.to_string(num_nodes))
      io.println("Topology: " <> topology_to_string(topology))
      io.println("Algorithm: " <> algorithm_to_string(algorithm))

      case algorithm {
        Gossip -> run_gossip_simulation_with_monitor(num_nodes, topology)
        PushSum -> run_pushsum_simulation_with_monitor(num_nodes, topology)
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
