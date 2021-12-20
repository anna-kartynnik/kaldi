#!/usr/bin/env bash
# Calls the neural network inference code.
# hk3129: Authored by me.

set -e
set -o pipefail
set -u

if [ -f ./path.sh ]; then
  . ./path.sh;
fi

nj=1
cmd=run.pl

iter=final
use_gpu=false

if [ $# -le 3 ]; then
  cat >&2 <<EOF
Usage: $0 [options] <test-data-dir> <nnet-model-dir> <output-dir>
 e.g.: $0 data/test data/exp data/exp/output
Note: <log-dir> defaults to <data-dir>/log, and
      <fbank-dir> defaults to <data-dir>/data
Options:
  --nj <nj>                            # number of parallel jobs.
  --cmd <run.pl|queue.pl <queue opts>> # how to run jobs.
  --use-gpu <true|false>               # whether to use GPU
EOF
   exit 1;
fi

. utils/parse_options.sh

DATA_DIR=$1
NNET_DIR=$2
OUTPUT_DIR=$3

# Data directory check
if [ ! -d $DATA_DIR ]; then
  echo "Error: $DATA_DIR directory does not exist."
  exit 1;
fi

# Nnet directory check
if [ ! -d $NNET_DIR ]; then
  echo "Error: $NNET_DIR directory does not exist."
  exit 1;
fi

mkdir -p $OUTPUT_DIR

steps/nnet3/compute_output.sh --nj $nj --cmd "$cmd" \
  --iter ${iter} --use-gpu ${use_gpu} \
  ${DATA_DIR} ${NNET_DIR} ${OUTPUT_DIR} || exit 1; 
