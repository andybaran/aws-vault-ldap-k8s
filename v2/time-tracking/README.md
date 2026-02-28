# Agent Time Tracking Dashboard

## Overview

This is a lightweight Flask web application that displays real-time status of all project agents working on the V2 refactoring. The dashboard reads from a CSV file (`agent_status.csv`) that is updated as agents begin, pause, and complete work.

## Prerequisites

- Python 3.8+
- Flask (`pip install flask`)

## Quick Start

```bash
cd v2/time-tracking
pip install flask
python dashboard.py
```

Then open **http://localhost:5050** in your browser.

## Features

- **Agent Cards**: Color-coded cards showing each agent's current status
- **Activity Log**: Scrollable table of the last 100 status updates
- **Auto-Refresh**: Dashboard polls the API every 5 seconds
- **Manual Refresh**: Click the refresh button for immediate update
- **REST API**: Agents can update their status via `POST /api/update/<agent_name>/<status>`

## Status Values

| Status | Color | Meaning |
|--------|-------|---------|
| `working` | 🟢 Green | Agent is actively working on a task |
| `waiting` | 🟡 Yellow | Agent is waiting for another agent |
| `completed` | 🔵 Blue | Agent has finished all assigned work |
| `idle` | ⚪ Gray | Agent has not started yet |
| `blocked` | 🔴 Red | Agent is blocked on an issue |

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Dashboard HTML page |
| `/api/status` | GET | JSON: current status of all agents + activity log |
| `/api/update/<agent>/<status>` | POST | Update an agent's status |

## CSV Format

The `agent_status.csv` file has three columns:

```csv
timestamp,agent_name,status
2026-02-28T20:15:00Z,Research Agent,working
2026-02-28T20:15:05Z,Python Agent,idle
```

This file is the single source of truth for the dashboard and is appended to as agents report status changes.
