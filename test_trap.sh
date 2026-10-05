#!/bin/sh
cleanup() {
    echo 'Trap fired: cleanup called'
    trap - INT TERM
}
test_loop() {
    interrupted=0
    trap 'cleanup; interrupted=1' INT TERM
    echo 'Testing in test_loop...'
    if [ " \
