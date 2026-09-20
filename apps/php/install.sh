#!/bin/sh
# modules/30-php.sh — shared / FPM-harden / CLI PHP drop-ins + one FPM pool
# Do not put disable_functions on CLI. Bee needs exec.

echo "STEP 30: PHP drop-ins and FPM pool"

tune_php
tune_php_fpm
