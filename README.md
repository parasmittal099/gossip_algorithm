This project implements gossip-type algorithms using the actor model in Gleam to study convergence behavior in distributed systems. The simulation includes two main algorithms: the Gossip Algorithm for information propagation (where actors spread rumors by randomly selecting neighbors until each actor hears the rumor 10 times) and the Push-Sum Algorithm for distributed sum computation (where actors maintain s and w values, send half to neighbors, and converge when the s/w ratio stabilizes within 10^-10 over 3 consecutive rounds). The system tests four different network topologies - Full Network (every actor connects to all others), 3D Grid (cube arrangement with 6 neighbors), Line (linear chain), and Imperfect 3D Grid (3D grid plus one random neighbor) - to analyze how network structure affects convergence time and message overhead in asynchronous distributed algorithms.

Project still under construction

# Build the project

gleam build

# Run the simulation

gleam run gossipprotocol <numNodes> <topology> <algorithm>

# Examples:

gleam run gossipprotocol 100 full gossip
# gossip_algorithm
