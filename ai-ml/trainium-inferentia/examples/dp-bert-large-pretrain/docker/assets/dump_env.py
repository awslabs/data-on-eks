#!/usr/bin/env python3
# Test script to dump the current environment, Neuron devices, EFA devices, etc. for
# troubleshooting
import os
import sys
import subprocess

print("Environment variables:")
for key in os.environ.keys():
    print(f"{key} -> {os.environ[key]}")

print("\nCommandline Args:")
for i,a in enumerate(sys.argv):
    print(f"{i}: {a}")

neuron_devs = subprocess.check_output("find /dev/ -name neur*", shell=True)
print(f"\nNeuron devices:\n{neuron_devs.decode()}")

pci_devs = subprocess.check_output("lspci", shell=True)
print(f"\nPCI devices:\n{pci_devs.decode()}")

try:
    efa_devs = subprocess.check_output("/opt/amazon/efa/bin/fi_info -p efa", shell=True)
    print(f"\nEFA devices:\n{efa_devs.decode()}")
except subprocess.CalledProcessError as e:
    print("\nNo EFA detected")

pip_packages = subprocess.check_output("pip3 list|grep -e neuron -e torch", shell=True)
print(f"\nPIP packages:\n{pip_packages.decode()}")
