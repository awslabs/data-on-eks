import asyncio
import argparse
from producers import run_all_producers

def main():
    parser = argparse.ArgumentParser(description='Cat Cafe Data Producers')
    parser.add_argument(
        '--bootstrap-servers', 
        default='localhost:9094',
        help='Kafka bootstrap servers (default: localhost:9094)'
    )
    
    args = parser.parse_args()
    bootstrap_servers = [args.bootstrap_servers]
    
    try:
        asyncio.run(run_all_producers(bootstrap_servers))
    except KeyboardInterrupt:
        print('\nShutting down producers...')

if __name__ == "__main__":
    main()
