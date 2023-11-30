#!/bin/bash

# Wait for nodes to be ready
kubectl wait --for=condition=Ready node --all --timeout=10m
