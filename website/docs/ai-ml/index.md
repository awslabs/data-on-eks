---
title: AI for Data
sidebar_position: 1
sidebar_label: Overview
---

import '@site/src/css/datastack-tiles.css';
import AIforDataHero from '@site/src/components/AIforData/AIforDataHero';

<AIforDataHero />

This section provides production-ready reference architectures for AI agents built for data platforms and data workloads. Each reference architecture is a working agent you can deploy and run against a real system. The architectures span various data frameworks and distributed databases, including both AWS managed services and open source. On the agent side, we leverage open source agentic frameworks like LangGraph as well as AWS managed services like Bedrock AgentCore. The goal is to give data teams a concrete starting point for building agents that solve their specific operational problems.

### Why Agents for Data Platforms?

Every data team has the same problem. Something breaks at 2 AM. A Spark job fails silently. A metric drops and nobody notices for hours. A pipeline produces bad data and three downstream teams build reports on it before anyone catches it.

The fix is always the same: someone senior logs in, runs a dozen queries, cross-references dashboards, checks configs, and eventually finds the one thing that went wrong. It takes 30 minutes if you're lucky. Hours if you're not.

What if that person didn't need to wake up?

## The Shift from Dashboards to Agents

Dashboards tell you something is wrong. Agents tell you why, and what to do about it.

An AI agent for data is software that can investigate problems the way a senior engineer would. It looks at the symptoms, decides what to check, runs the queries, reads the results, and writes up a conclusion. It does this in seconds, not hours. It does it for every incident, not just the ones that page someone.

This isn't about replacing engineers. It's about giving every alert the same quality of investigation that today only happens when the right person is online.

## Where Agents Make Sense

The best use cases share a pattern: a human would need to run multiple queries across multiple dimensions to find the answer.

**Anomaly investigation.** A business metric drops. The agent drills into every dimension (region, device, campaign, creative) simultaneously and identifies the exact segment causing the drop.

**Job failure diagnosis.** A Spark job fails or runs 10x slower than usual. The agent reads the execution plan, checks for data skew, examines memory usage, and pinpoints whether it's a code change, a data change, or an infrastructure issue.

**Pipeline health.** Data arrives late or with unexpected schema changes. The agent traces the lineage, identifies where the break happened, and determines impact on downstream consumers.

**Performance optimization.** Queries that used to run in seconds now take minutes. The agent analyzes execution profiles, identifies missing indexes or bad join strategies, and recommends specific fixes.

**Upgrade readiness.** Before upgrading a platform version, the agent reviews your workloads against the changelog, identifies breaking changes that affect your specific usage patterns, and flags what needs attention.

## How These Reference Architectures Work

Each reference architecture in this section is a complete, working agent you can deploy and run against a real data platform. You'll see the agent receive a problem, decide what to investigate, execute queries, and produce a written report with root cause and recommended actions.

The goal is to give data teams a starting point. Take a reference architecture, swap in your data platform, adjust the investigation logic for your domain, and you have an agent that handles your specific operational problems.

Browse the reference architectures in the sidebar to get started.
