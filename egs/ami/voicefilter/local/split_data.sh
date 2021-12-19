#!/usr/bin/env bash

# Copyright 

# Note: this is called by ../run.sh.

# To be run from one directory above this script.

. ./path.sh

# [TODO] check existing directories
if [ $# -ne 3 ]; then
  echo "Usage: $0 /path/to/data /path/to/output /path/to/splits"
#  echo "e.g. $0 /foo/bar/AMI ihm"
  exit 1;
fi

echo "$0 $@"  # Print the command line for logging.

DATA_DIR=$1
OUTPUT_DIR=$2
SPLITS_DIR=$3

# Data directory check
if [ ! -d $DATA_DIR ]; then
  echo "Error: $DATA_DIR directory does not exist."
  exit 1;
fi

mkdir -p $OUTPUT_DIR
mkdir -p $OUTPUT_DIR/temp
LOCAL_OUTPUT_DIR=$OUTPUT_DIR/temp

# [TODO] check that wav.scp exists?
if [[ $DATA_DIR == *"enrollment"* ]]; then
  awk '{print $1}' $DATA_DIR/wav.scp | \
    perl -ne 'split; $_ =~ m/AMI_(.*)_.*/; print "$1 $_"' > $LOCAL_OUTPUT_DIR/meetings2utt
else
  awk '{print $1}' $DATA_DIR/wav.scp | \
    perl -ne 'split; $_ =~ m/AMI_(.*)_H.*/; print "$1 $_"' > $LOCAL_OUTPUT_DIR/meetings2utt
fi

for dset in train dev "eval"; do
  mkdir -p $OUTPUT_DIR/$dset

  join $SPLITS_DIR/split_$dset.orig $LOCAL_OUTPUT_DIR/meetings2utt | \
    awk '{print $2}' - > $LOCAL_OUTPUT_DIR/utt_$dset
  for f in wav.scp utt2spk; do
    join $DATA_DIR/$f $LOCAL_OUTPUT_DIR/utt_$dset > $OUTPUT_DIR/$dset/$f || exit 1;
  done
  utils/utt2spk_to_spk2utt.pl <$OUTPUT_DIR/$dset/utt2spk >$OUTPUT_DIR/$dset/spk2utt || exit 1;

  utils/validate_data_dir.sh --no-feats --no-text $OUTPUT_DIR/$dset || exit 1;
done

rm -r $LOCAL_OUTPUT_DIR

echo AMI data splitting succeeded.






