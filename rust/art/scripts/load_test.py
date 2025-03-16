#!/usr/bin/env python3

"""
Load Testing Script for Art Git Repository Browser

This script performs load testing on the Art application to simulate high traffic
and measure performance under different loads.

Usage:
    python load_test.py [options]

Options:
    --url URL             Base URL of the Art instance (default: http://localhost:3000)
    --clients NUM         Number of simulated clients (default: 50)
    --duration SEC        Test duration in seconds (default: 60)
    --ramp-up SEC         Ramp-up period in seconds (default: 10)
    --repo REPO           Repository name to test against (default: art)
    --scenario SCENARIO   Test scenario (browse, api, mixed) (default: mixed)
    --verbose             Enable verbose output
    --json                Output results in JSON format
    --output FILE         Save results to a file
    --timeout SEC         Request timeout in seconds (default: 10)
    --statsd HOST:PORT    Send metrics to StatsD server
    --help                Show this help message
"""

import argparse
import asyncio
import aiohttp
import json
import logging
import random
import statistics
import sys
import time
from collections import defaultdict
from datetime import datetime
from urllib.parse import urljoin

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("art-load-tester")

# Test result storage
results = {
    "summary": {},
    "requests": defaultdict(list),
    "errors": defaultdict(int),
    "status_codes": defaultdict(int),
}

# Common repository paths to test
PATHS = [
    "/",
    "/repos",
    "/repos/{repo}",
    "/repos/{repo}/branches",
    "/repos/{repo}/tags",
    "/repos/{repo}/commits",
    "/repos/{repo}/tree/master",
    "/repos/{repo}/blob/master/README.md",
    "/repos/{repo}/raw/master/README.md",
    "/api/repos",
    "/api/repos/{repo}",
    "/api/repos/{repo}/branches",
    "/api/repos/{repo}/tags",
    "/api/repos/{repo}/commits",
    "/api/health",
]

# Weighted scenarios for more realistic testing
SCENARIOS = {
    "browse": [
        (70, "/repos/{repo}"),
        (50, "/repos/{repo}/tree/master"),
        (30, "/repos/{repo}/commits"),
        (20, "/repos/{repo}/blob/master/README.md"),
        (10, "/repos/{repo}/branches"),
        (5, "/repos/{repo}/tags"),
        (5, "/"),
    ],
    "api": [
        (50, "/api/repos/{repo}"),
        (30, "/api/repos/{repo}/commits"),
        (20, "/api/repos/{repo}/branches"),
        (15, "/api/repos/{repo}/tags"),
        (10, "/api/health"),
        (5, "/api/repos"),
    ],
    "mixed": [
        (40, "/repos/{repo}"),
        (30, "/repos/{repo}/tree/master"),
        (25, "/repos/{repo}/commits"),
        (20, "/repos/{repo}/blob/master/README.md"),
        (15, "/api/repos/{repo}"),
        (10, "/api/repos/{repo}/commits"),
        (5, "/api/health"),
        (5, "/"),
    ],
}

class StatsClient:
    """Simple StatsD client for sending metrics"""

    def __init__(self, host=None, port=None):
        self.addr = None
        self.socket = None

        if host and port:
            import socket
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.addr = (host, port)

    def timing(self, metric, value_ms):
        """Send a timing metric"""
        if not self.addr:
            return
        self._send(f"{metric}:{value_ms}|ms")

    def increment(self, metric, value=1):
        """Increment a counter metric"""
        if not self.addr:
            return
        self._send(f"{metric}:{value}|c")

    def _send(self, data):
        """Send raw data to StatsD"""
        if not self.addr:
            return
        try:
            self.socket.sendto(data.encode('utf-8'), self.addr)
        except:
            pass  # Silently fail on StatsD errors


async def fetch(session, url, repo, statsd, timeout, client_id):
    """Fetch a URL and record metrics"""
    path = url.format(repo=repo)
    full_url = urljoin(session.base_url, path)

    try:
        start_time = time.time()
        async with session.get(full_url, timeout=timeout) as response:
            response_time = time.time() - start_time
            response_time_ms = response_time * 1000

            # Record result
            status = response.status
            results["requests"][path].append(response_time_ms)
            results["status_codes"][status] += 1

            # Send metrics to StatsD if configured
            statsd.timing(f"art.response_time.{status}.{path.replace('/', '_')}", response_time_ms)
            statsd.increment(f"art.requests.{status}.{path.replace('/', '_')}")

            # Log if verbose
            if args.verbose:
                logger.info(f"Client {client_id:3d}: {path} -> {status} ({response_time_ms:.2f}ms)")

            return status, response_time_ms

    except asyncio.TimeoutError:
        results["errors"]["timeout"] += 1
        statsd.increment("art.errors.timeout")
        if args.verbose:
            logger.error(f"Client {client_id:3d}: Timeout accessing {path}")
        return 0, 0

    except aiohttp.ClientError as e:
        results["errors"]["client_error"] += 1
        statsd.increment("art.errors.client")
        if args.verbose:
            logger.error(f"Client {client_id:3d}: Error accessing {path}: {e}")
        return 0, 0

    except Exception as e:
        results["errors"]["other"] += 1
        statsd.increment("art.errors.other")
        if args.verbose:
            logger.error(f"Client {client_id:3d}: Unexpected error for {path}: {e}")
        return 0, 0


async def worker(client_id, repo, scenario_name, duration, statsd, timeout):
    """Worker that simulates a client browsing the repository"""
    # Create a session for this client
    async with aiohttp.ClientSession() as session:
        # Add base_url attribute to session for url joining
        session.base_url = args.url

        scenario = SCENARIOS.get(scenario_name, SCENARIOS["mixed"])
        weights, paths = zip(*scenario)

        start_time = time.time()
        request_count = 0

        # Calculate ramp-up delay based on client ID
        if args.ramp_up > 0 and client_id > 0:
            delay = (args.ramp_up / args.clients) * client_id
            await asyncio.sleep(delay)

        # Run until the test duration is reached
        while time.time() - start_time < duration:
            # Pick a random path based on weights
            path = random.choices(paths, weights=weights, k=1)[0]

            # Fetch the URL
            await fetch(session, path, repo, statsd, timeout, client_id)

            request_count += 1

            # Add some randomness to simulate real user behavior
            await asyncio.sleep(random.uniform(0.1, 1.0))

        return request_count


async def run_load_test(args, statsd):
    """Run the load test with the given parameters"""
    logger.info(f"Starting load test with {args.clients} clients for {args.duration}s")
    logger.info(f"Target: {args.url}, Repository: {args.repo}, Scenario: {args.scenario}")

    start_time = time.time()

    # Create tasks for all clients
    tasks = [
        worker(i, args.repo, args.scenario, args.duration, statsd, args.timeout)
        for i in range(args.clients)
    ]

    # Run all tasks concurrently
    request_counts = await asyncio.gather(*tasks)
    total_requests = sum(request_counts)

    end_time = time.time()
    duration = end_time - start_time

    # Calculate summary metrics
    results["summary"] = {
        "start_time": datetime.fromtimestamp(start_time).isoformat(),
        "end_time": datetime.fromtimestamp(end_time).isoformat(),
        "duration": duration,
        "total_requests": total_requests,
        "requests_per_second": total_requests / duration,
        "clients": args.clients,
        "scenario": args.scenario,
        "target_url": args.url,
        "repository": args.repo,
        "errors": sum(results["errors"].values()),
        "error_rate": sum(results["errors"].values()) / total_requests if total_requests > 0 else 0,
    }

    # Calculate per-endpoint statistics
    endpoint_stats = {}
    for path, times in results["requests"].items():
        if not times:
            continue

        endpoint_stats[path] = {
            "count": len(times),
            "min_ms": min(times),
            "max_ms": max(times),
            "avg_ms": statistics.mean(times),
            "median_ms": statistics.median(times),
            "p95_ms": percentile(times, 95),
            "p99_ms": percentile(times, 99),
        }

    results["endpoints"] = endpoint_stats

    return results


def percentile(data, percentile):
    """Calculate a percentile from the data"""
    if not data:
        return 0
    size = len(data)
    sorted_data = sorted(data)
    return sorted_data[int((size * percentile) / 100)]


def print_results(results):
    """Print the test results in a human-readable format"""
    summary = results["summary"]

    print("\n" + "=" * 80)
    print(f"ART LOAD TEST RESULTS")
    print("=" * 80)
    print(f"Target:          {summary['target_url']}")
    print(f"Repository:      {summary['repository']}")
    print(f"Scenario:        {summary['scenario']}")
    print(f"Duration:        {summary['duration']:.2f} seconds")
    print(f"Clients:         {summary['clients']}")
    print(f"Total Requests:  {summary['total_requests']}")
    print(f"Requests/sec:    {summary['requests_per_second']:.2f}")
    print(f"Error Rate:      {summary['error_rate']*100:.2f}%")

    # Status code breakdown
    print("\nStatus Codes:")
    for status, count in sorted(results["status_codes"].items()):
        print(f"  {status}: {count}")

    # Error breakdown
    if results["errors"]:
        print("\nErrors:")
        for error, count in sorted(results["errors"].items()):
            print(f"  {error}: {count}")

    # Endpoint performance
    print("\nEndpoint Performance:")
    print(f"{'Path':<40} {'Count':>8} {'Avg (ms)':>10} {'Median':>10} {'95%':>10} {'99%':>10} {'Min':>10} {'Max':>10}")
    print("-" * 110)

    for path, stats in sorted(results["endpoints"].items()):
        print(f"{path:<40} {stats['count']:>8} {stats['avg_ms']:>10.2f} {stats['median_ms']:>10.2f} "
              f"{stats['p95_ms']:>10.2f} {stats['p99_ms']:>10.2f} {stats['min_ms']:>10.2f} {stats['max_ms']:>10.2f}")

    print("=" * 80)


def parse_args():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description="Load test for Art Git Repository Browser")
    parser.add_argument("--url", default="http://localhost:3000", help="Base URL of the Art instance")
    parser.add_argument("--clients", type=int, default=50, help="Number of simulated clients")
    parser.add_argument("--duration", type=int, default=60, help="Test duration in seconds")
    parser.add_argument("--ramp-up", type=int, default=10, help="Ramp-up period in seconds")
    parser.add_argument("--repo", default="art", help="Repository name to test against")
    parser.add_argument("--scenario", default="mixed", choices=["browse", "api", "mixed"],
                        help="Test scenario (browse, api, mixed)")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose output")
    parser.add_argument("--json", action="store_true", help="Output results in JSON format")
    parser.add_argument("--output", help="Save results to a file")
    parser.add_argument("--timeout", type=int, default=10, help="Request timeout in seconds")
    parser.add_argument("--statsd", help="Send metrics to StatsD server (format: host:port)")

    return parser.parse_args()


async def main():
    """Main entry point"""
    global args
    args = parse_args()

    # Set up StatsD client if configured
    statsd_host = None
    statsd_port = None
    if args.statsd:
        try:
            statsd_host, statsd_port = args.statsd.split(":")
            statsd_port = int(statsd_port)
            logger.info(f"Sending metrics to StatsD at {statsd_host}:{statsd_port}")
        except:
            logger.error("Invalid StatsD address format. Use host:port")

    statsd = StatsClient(statsd_host, statsd_port)

    try:
        # Run the load test
        results = await run_load_test(args, statsd)

        # Print or save results
        if args.json:
            # Convert defaultdicts to regular dicts for JSON serialization
            for key, value in results.items():
                if isinstance(value, defaultdict):
                    results[key] = dict(value)

            if args.output:
                with open(args.output, 'w') as f:
                    json.dump(results, f, indent=2)
            else:
                print(json.dumps(results, indent=2))
        else:
            print_results(results)

            if args.output:
                with open(args.output, 'w') as f:
                    f.write("Art Load Test Results\n\n")
                    for key, value in results["summary"].items():
                        f.write(f"{key}: {value}\n")
                    f.write("\nSee full results in the console output.\n")

    except KeyboardInterrupt:
        logger.info("Load test interrupted by user")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Error during load test: {e}")
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
