# Team Members
Paras Mittal 
Sridhar Kumar

# What Is Working?
We are able to simulate a gossip algorithm for all the topologies with varying convergance time and different limits of each topology.
We are also able to simulate a push-sum algorithm for all the topologies with varying convergance time and different limits of each topology.


# Largest Network Size for each Topology and Algorithm:
Gossip:
Line:  50
Full:  1000
3D:    2500
imp3D: 5000

Push-Sum
Line:  100
Full:  2500
3D:    10000
imp3D: 10000





# Description

This project implements gossip-type algorithms using the actor model in Gleam to study convergence behavior in distributed systems. The simulation includes two main algorithms: the Gossip Algorithm for information propagation (where actors spread rumors by randomly selecting neighbors until each actor hears the rumor 10 times) and the Push-Sum Algorithm for distributed sum computation (where actors maintain s and w values, send half to neighbors, and converge when the s/w ratio stabilizes within 10^-10 over 3 consecutive rounds). The system tests four different network topologies - Full Network (every actor connects to all others), 3D Grid (cube arrangement with 6 neighbors), Line (linear chain), and Imperfect 3D Grid (3D grid plus one random neighbor) - to analyze how network structure affects convergence time and message overhead in asynchronous distributed algorithms.



# Build the project

gleam build

# Run the simulation

gleam run -- <number of nodes> <network topology> <algorithm>

# Examples:

gleam run gossipprotocol 100 full gossip
gleam run gossipprotocol 100 line push-sum
gleam run gossipprotocol 100 3D push-sum
gleam run gossipprotocol 100 imp3d push-sum