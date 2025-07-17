#!/bin/bash

for table in filter nat mangle raw security; do
  sudo iptables -t $table -F
  sudo ip6tables -t $table -F
done
