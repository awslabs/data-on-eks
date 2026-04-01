#!/usr/bin/env python3
"""
Celeborn worker rolling restart using decommission API.

This script uses Celeborn's decommission API for graceful worker restarts.
It provides better observability and fewer transient errors compared to
simple pod deletion.

Service topology created by the official Celeborn Helm chart:
  Master headless svc : <release>-master-svc.<namespace>.svc.cluster.local
  Worker headless svc : <release>-worker-svc.<namespace>.svc.cluster.local
  Per-pod stable DNS  : <release>-worker-N.<release>-worker-svc.<namespace>.svc.cluster.local
  Master HTTP port    : 9098  (celeborn.master.http.port)
  Worker HTTP port    : 9096  (celeborn.worker.http.port)

API call routing:
  Decommission a worker  -> POST <worker-pod>:<worker-port>/api/v1/workers/exit
  Check cluster state    -> GET  <master-pod>:<master-port>/api/v1/workers
  (master has authoritative view of registered/decommissioning/lost workers)

Prerequisites:
  - kubectl configured for the target cluster
  - Python 3.7+
  - celeborn.network.bind.preferIpAddress=false in Helm values (see NOTE below)

NOTE — add this to your Helm values BEFORE running rolling restarts:
  celeborn:
    celeborn.network.bind.preferIpAddress: "false"

  Without it, workers register using pod IP. After restart the pod IP changes.
  The master keeps the stale IP; clients can't fetch from the restarted worker.
  With preferIpAddress=false, workers register using their stable DNS hostname.
  Source: https://celeborn.apache.org/docs/latest/deploy_on_k8s/

Usage:
  ./rolling-restart-celeborn-with-decommission.py
  ./rolling-restart-celeborn-with-decommission.py --namespace celeborn --release celeborn
  ./rolling-restart-celeborn-with-decommission.py --dry-run
"""

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from typing import Optional, Dict, Any, List


class Colors:
    """ANSI color codes for terminal output."""
    RESET = '\033[0m'
    INFO = '\033[94m'
    OK = '\033[92m'
    WARN = '\033[93m'
    FAIL = '\033[91m'


def log(msg: str, level: str = 'info') -> None:
    """Print timestamped log message."""
    timestamp = datetime.now().strftime('%H:%M:%S')
    prefix = {
        'info': f'{Colors.INFO}ℹ{Colors.RESET}',
        'ok': f'{Colors.OK}✓{Colors.RESET}',
        'warn': f'{Colors.WARN}⚠{Colors.RESET}',
        'fail': f'{Colors.FAIL}✗{Colors.RESET}',
        'log': ''
    }.get(level, '')

    print(f"[{timestamp}] {prefix}  {msg}")


def fail(msg: str) -> None:
    """Print error message and exit."""
    log(msg, 'fail')
    sys.exit(1)


def run_kubectl(args: List[str], check: bool = True, capture: bool = True) -> Optional[str]:
    """Execute kubectl command and return output."""
    cmd = ['kubectl'] + args
    try:
        if capture:
            result = subprocess.run(cmd, capture_output=True, text=True, check=check, env=os.environ.copy())
            return result.stdout.strip()
        else:
            subprocess.run(cmd, check=check, env=os.environ.copy())
            return None
    except subprocess.CalledProcessError as e:
        if check:
            fail(f"kubectl command failed: {' '.join(cmd)}\n{e.stderr}")
        return None


def curl_via_kubectl(namespace: str, pod: str, url: str, method: str = 'GET',
                     data: Optional[str] = None) -> Optional[str]:
    """Execute curl command via kubectl exec."""
    curl_cmd = ['curl', '-sf', '--max-time', '10']

    if method == 'POST':
        curl_cmd.extend(['-X', 'POST', '-H', 'Content-Type: application/json'])
        if data:
            curl_cmd.extend(['-d', data])

    curl_cmd.append(url)

    try:
        result = run_kubectl([
            'exec', '-n', namespace, pod, '--',
            *curl_cmd
        ], check=False)
        return result
    except Exception:
        return None


class CelebornCluster:
    """Manages Celeborn cluster operations."""

    def __init__(self, namespace: str, release: str, master_port: int,
                 worker_port: int, dry_run: bool = False):
        self.namespace = namespace
        self.release = release
        self.master_port = master_port
        self.worker_port = worker_port
        self.dry_run = dry_run

        self.statefulset = f"{release}-worker"
        self.master_svc = f"{release}-master-svc"
        self.worker_svc = f"{release}-worker-svc"

        self.master_reachable = False

    def worker_pod_dns(self, ordinal: int) -> str:
        """Get stable DNS name for worker pod."""
        return f"{self.statefulset}-{ordinal}.{self.worker_svc}.{self.namespace}.svc.cluster.local"

    def get_statefulset_replicas(self) -> int:
        """Get number of worker replicas."""
        output = run_kubectl([
            'get', 'statefulset', self.statefulset,
            '-n', self.namespace,
            '-o', 'jsonpath={.spec.replicas}'
        ])
        return int(output) if output else 0

    def get_master_replicas(self) -> int:
        """Get number of master replicas."""
        output = run_kubectl([
            'get', 'statefulset', f"{self.release}-master",
            '-n', self.namespace,
            '-o', 'jsonpath={.spec.replicas}'
        ], check=False)
        return int(output) if output else 3

    def get_master_workers_json(self) -> Optional[Dict[str, Any]]:
        """Query master API for worker states."""
        master_replicas = self.get_master_replicas()

        for m in range(master_replicas):
            mpod = f"{self.release}-master-{m}"
            mpod_dns = f"{mpod}.{self.master_svc}.{self.namespace}.svc.cluster.local"
            url = f"http://{mpod_dns}:{self.master_port}/api/v1/workers"

            resp = curl_via_kubectl(self.namespace, mpod, url)
            if resp:
                try:
                    data = json.loads(resp)
                    if 'workers' in data:
                        return data
                except json.JSONDecodeError:
                    continue

        return None

    def decommission_worker(self, pod: str) -> bool:
        """Send decommission request to worker."""
        pod_dns = f"{pod}.{self.worker_svc}.{self.namespace}.svc.cluster.local"
        url = f"http://{pod_dns}:{self.worker_port}/api/v1/workers/exit"
        data = '{"type":"DECOMMISSION"}'

        if self.dry_run:
            log(f"[DRY-RUN] POST {url}", 'info')
            return True

        resp = curl_via_kubectl(self.namespace, pod, url, method='POST', data=data)
        return resp is not None

    def wait_for_drain(self, pod: str, dns: str, timeout: int) -> bool:
        """Wait for worker to drain from master's decommissioning list."""
        start_time = time.time()

        while True:
            elapsed = int(time.time() - start_time)
            if elapsed >= timeout:
                log(f"Drain timeout ({elapsed}s) — forcing delete", 'warn')
                return False

            # Check if pod self-terminated
            result = run_kubectl(['get', 'pod', pod, '-n', self.namespace], check=False)
            if not result:
                log(f"Pod {pod} self-exited after drain ({elapsed}s)", 'ok')
                return True

            if self.master_reachable:
                wjson = self.get_master_workers_json()
                if wjson:
                    decomm_workers = wjson.get('decommissioningWorkers', [])
                    still_decomm = any(pod in str(w) or dns in str(w) for w in decomm_workers)

                    if not still_decomm:
                        log(f"Worker {pod} drained — no longer in master decommissioningWorkers ({elapsed}s)", 'ok')
                        return True

                    log(f"Still decommissioning on master... elapsed={elapsed}s", 'info')

            time.sleep(15)

    def delete_pod(self, pod: str) -> None:
        """Delete pod and wait for termination."""
        log(f"Deleting pod {pod} (StatefulSet will recreate with same PVCs)...", 'info')

        if self.dry_run:
            log(f"[DRY-RUN] kubectl delete pod {pod} -n {self.namespace}", 'info')
            return

        run_kubectl(['delete', 'pod', pod, '-n', self.namespace, '--wait=false'])
        time.sleep(5)

        # Wait for old pod to terminate
        log(f"Waiting for old {pod} to fully terminate...", 'info')
        term_start = time.time()

        while run_kubectl(['get', 'pod', pod, '-n', self.namespace], check=False):
            elapsed = int(time.time() - term_start)
            if elapsed >= 60:
                log("Old pod still terminating after 60s, continuing anyway", 'warn')
                break
            time.sleep(2)

        log(f"Old {pod} terminated", 'ok')

    def wait_for_ready(self, pod: str, timeout: int) -> bool:
        """Wait for pod to be recreated and Ready."""
        log(f"Waiting for {pod} to be recreated and Ready (timeout: {timeout}s)...", 'info')

        if self.dry_run:
            return True

        start_time = time.time()

        while True:
            elapsed = int(time.time() - start_time)
            if elapsed >= timeout:
                return False

            phase = run_kubectl([
                'get', 'pod', pod, '-n', self.namespace,
                '-o', 'jsonpath={.status.phase}'
            ], check=False) or 'Pending'

            ready = run_kubectl([
                'get', 'pod', pod, '-n', self.namespace,
                '-o', 'jsonpath={.status.conditions[?(@.type=="Ready")].status}'
            ], check=False) or 'False'

            log(f"phase={phase} ready={ready} elapsed={elapsed}s", 'info')

            if phase == 'Running' and ready == 'True':
                log(f"{pod} is Ready", 'ok')
                return True

            time.sleep(10)

    def verify_registration(self, pod: str, dns: str) -> bool:
        """Verify worker is registered on master."""
        if not self.master_reachable:
            log("Skipping master registration check (master unreachable)", 'warn')
            time.sleep(30)
            return True

        log(f"Confirming {pod} re-registered on Celeborn master...", 'info')
        start_time = time.time()

        while True:
            elapsed = int(time.time() - start_time)
            if elapsed >= 90:
                break

            wjson = self.get_master_workers_json()
            if wjson:
                workers = wjson.get('workers', [])
                found = any(pod in str(w) or dns in str(w) for w in workers)

                if found:
                    log(f"{pod} registered on Celeborn master", 'ok')
                    return True

            log(f"Waiting for master registration... {elapsed}s", 'info')
            time.sleep(10)

        fail(f"{pod} Ready but NOT registered on master after 90s.\n"
             "Check worker logs and verify celeborn.network.bind.preferIpAddress=false is set.")

    def stability_wait(self, pod: str, duration: int = 120) -> None:
        """Wait for pod to stabilize before next restart."""
        log(f"Waiting {duration}s for {pod} to stabilize before next restart...", 'info')

        if self.dry_run:
            return

        start_time = time.time()

        while True:
            elapsed = int(time.time() - start_time)
            if elapsed >= duration:
                break

            phase = run_kubectl([
                'get', 'pod', pod, '-n', self.namespace,
                '-o', 'jsonpath={.status.phase}'
            ], check=False) or 'Unknown'

            ready = run_kubectl([
                'get', 'pod', pod, '-n', self.namespace,
                '-o', 'jsonpath={.status.conditions[?(@.type=="Ready")].status}'
            ], check=False) or 'False'

            if phase != 'Running' or ready != 'True':
                fail(f"{pod} became unhealthy during stability wait (phase={phase} ready={ready})")

            log(f"Stability check: phase={phase} ready={ready} elapsed={elapsed}s/{duration}s", 'info')
            time.sleep(15)

        log(f"{pod} stable for {duration}s", 'ok')

    def print_summary(self) -> None:
        """Print cluster summary."""
        print("\n" + "━" * 70)
        log("Rolling restart complete — all workers restarted", 'ok')
        print()

        log("Pod status:", 'log')
        run_kubectl([
            'get', 'pods', '-n', self.namespace,
            '-l', 'app.kubernetes.io/component=worker',
            '-o', 'wide'
        ], capture=False, check=False)

        print()

        if self.master_reachable:
            log("Cluster worker registry (from master API):", 'log')
            wjson = self.get_master_workers_json()
            if wjson:
                workers = wjson.get('workers', [])
                print(f"  Active registered workers : {len(workers)}")
                for w in workers:
                    host = w.get('host', '?')
                    used_slots = w.get('usedSlots', 0)
                    print(f"    {host}  usedSlots={used_slots}")

                for key in ['lostWorkers', 'excludedWorkers', 'decommissioningWorkers', 'shutdownWorkers']:
                    val = wjson.get(key, [])
                    if val:
                        print(f"  {key}: {len(val)}")


def main():
    parser = argparse.ArgumentParser(
        description='Celeborn worker rolling restart with decommission API',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument('--namespace', default='celeborn', help='Kubernetes namespace')
    parser.add_argument('--release', default='celeborn', help='Helm release name')
    parser.add_argument('--master-http-port', type=int, default=9098, help='Master HTTP port')
    parser.add_argument('--worker-http-port', type=int, default=9096, help='Worker HTTP port')
    parser.add_argument('--drain-timeout', type=int, default=600, help='Drain timeout in seconds')
    parser.add_argument('--ready-timeout', type=int, default=300, help='Ready timeout in seconds')
    parser.add_argument('--dry-run', action='store_true', help='Dry run mode')

    args = parser.parse_args()

    # Initialize cluster manager
    cluster = CelebornCluster(
        namespace=args.namespace,
        release=args.release,
        master_port=args.master_http_port,
        worker_port=args.worker_http_port,
        dry_run=args.dry_run
    )

    # Print configuration
    log("Celeborn rolling restart", 'log')
    log(f"  Namespace    : {args.namespace}", 'log')
    log(f"  Release      : {args.release}", 'log')
    log(f"  StatefulSet  : {cluster.statefulset}", 'log')
    log(f"  Master svc   : {cluster.master_svc}.{args.namespace}.svc.cluster.local", 'log')
    log(f"  Worker svc   : {cluster.worker_svc}.{args.namespace}.svc.cluster.local", 'log')
    log(f"  Drain timeout: {args.drain_timeout}s", 'log')
    log(f"  Ready timeout: {args.ready_timeout}s", 'log')

    if args.dry_run:
        log("DRY-RUN mode — no changes will be made", 'warn')

    print()

    # Preflight checks
    result = run_kubectl(['get', 'statefulset', cluster.statefulset, '-n', args.namespace], check=False)
    if result is None:
        fail(f"StatefulSet {cluster.statefulset} not found in namespace {args.namespace}")

    replicas = cluster.get_statefulset_replicas()
    log(f"Worker replicas: {replicas}", 'info')

    if replicas < 2:
        fail("Need at least 2 replicas for safe rolling restart")

    # Check preferIpAddress configuration
    configmap_data = run_kubectl([
        'get', 'configmap', f"{args.release}-conf",
        '-n', args.namespace,
        '-o', 'jsonpath={.data.celeborn-defaults\\.conf}'
    ], check=False) or ''

    if 'preferIpAddress' not in configmap_data:
        log("celeborn.network.bind.preferIpAddress not found in ConfigMap", 'warn')
        log("Workers may register with pod IP instead of DNS hostname.", 'warn')
        log("After restart, master may not route to the new pod IP correctly.", 'warn')
        log("Add 'celeborn.network.bind.preferIpAddress: false' to Helm values.", 'warn')
        print()

    # Check master API reachability
    log("Checking master API reachability...", 'info')
    master_json = cluster.get_master_workers_json()

    if master_json:
        active = len(master_json.get('workers', []))
        log(f"Master API reachable — {active} active workers registered", 'ok')
        cluster.master_reachable = True
    else:
        log("Master API unreachable — registration checks will be skipped", 'warn')
        cluster.master_reachable = False

    print()

    # Rolling restart — highest ordinal first
    for i in range(replicas - 1, -1, -1):
        pod = f"{cluster.statefulset}-{i}"
        dns = cluster.worker_pod_dns(i)
        step = replicas - i

        print(f"\n{'━' * 70}")
        log(f"[{step}/{replicas}] {pod}", 'log')
        log(f"Stable DNS : {dns}", 'info')

        phase = run_kubectl([
            'get', 'pod', pod, '-n', args.namespace,
            '-o', 'jsonpath={.status.phase}'
        ], check=False) or 'Unknown'

        log(f"Phase      : {phase}", 'info')

        # 1. Decommission
        decomm_ok = False
        if phase == 'Running':
            log("Sending decommission request...", 'info')
            if cluster.decommission_worker(pod):
                log("Decommission accepted", 'info')
                decomm_ok = True
            else:
                log("Decommission API returned empty response — proceeding with delete", 'warn')
        else:
            log("Pod not Running — skipping decommission API call", 'warn')

        # 2. Wait for drain
        if decomm_ok and not args.dry_run:
            log(f"Polling master for drain completion (timeout: {args.drain_timeout}s)...", 'info')
            cluster.wait_for_drain(pod, dns, args.drain_timeout)

        # 3. Delete pod
        cluster.delete_pod(pod)

        if args.dry_run:
            print()
            continue

        # 4. Wait for Ready
        if not cluster.wait_for_ready(pod, args.ready_timeout):
            fail(f"{pod} did not become Ready within {args.ready_timeout}s — aborting")

        # 5. Verify registration
        cluster.verify_registration(pod, dns)

        # 6. Stability wait
        cluster.stability_wait(pod, 120)

        print()

    # Print summary
    cluster.print_summary()


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
        sys.exit(1)
    except Exception as e:
        fail(f"Unexpected error: {e}")
