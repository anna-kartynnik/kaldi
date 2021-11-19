#!/usr/bin/env bash

. ./cmd.sh
. ./path.sh

NOISY_AUDIO_DIR="experiments/data/mix"
CLEAN_AUDIO_DIR="experiments/data/clean"
DATA_DIR="data/train_orig" # [TODO]

set -euo pipefail

# mkdir -p $OUTPUT_DIR

# Data preparation
local/prepare_data.sh $NOISY_AUDIO_DIR $CLEAN_AUDIO_DIR $DATA_DIR/noisy $DATA_DIR/clean

# [TODO] Split into train/dev/eval

# Feature extraction,
# if [ $stage -le 4 ]; then
#   for dset in train dev eval; do
#     steps/make_mfcc.sh --nj 15 --cmd "$train_cmd" data/$mic/$dset
#     steps/compute_cmvn_stats.sh data/$mic/$dset
#     utils/fix_data_dir.sh data/$mic/$dset
#   done
# fi

# Feature extraction for noisy audio
steps/make_fbank.sh --nj 2 --cmd "$train_cmd" $DATA_DIR/noisy

# Feature extraction for clean audio
steps/make_fbank.sh --nj 2 --cmd "$train_cmd" $DATA_DIR/clean