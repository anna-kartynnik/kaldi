#!/usr/bin/env bash
# hk3129: Authored by me

# To be run from .. (one directory up from here)


echo "$#"
if [ $# -lt 6 ]; then
  echo "Usage: $0 /path/to/noisy/features /path/to/xvectors /path/to/utt2spk /path/to/combined/features /path/to/logs --cmd cmd"
  exit 1;
fi

echo "$0 $@"  # Print the command line for logging.

NOISY_FEATURES_DIR=$1
XVECTORS_DIR=$2
UTT2SPK=$3
OUTPUT_FEATURES_DIR=$4
LOGS_DIR=$5/append

# Noisy features directory check
if [ ! -d $NOISY_FEATURES_DIR ]; then
  echo "Error: $NOISY_FEATURES_DIR directory does not exists."
  exit 1;
fi

# Xvectors directory check
if [ ! -d $XVECTORS_DIR ]; then
  echo "Error: $XVECTORS_DIR directory does not exists."
  exit 1;
fi

LOCAL_OUTPUT_DIR=data/local/temp
FEATURES_SCP=$NOISY_FEATURES_DIR/feats.scp
XVECTORS_SCP=$XVECTORS_DIR/xvector.scp
nj=2
cmd=run.pl

for f in $FEATURES_SCP $XVECTORS_SCP; do
  if [ ! -f $f ]; then
    echo "$0: no such file $f"
    exit 1;
  fi
done

mkdir -p $LOCAL_OUTPUT_DIR || exit 1;
mkdir -p $LOGS_DIR || exit 1;

# Copy spk2utt and utt2spk, they stay the same for combined vectors.
for f in spk2utt utt2spk; do
  cp $NOISY_FEATURES_DIR/$f $OUTPUT_FEATURES_DIR/$f || exit 1;
done

name=`basename $NOISY_FEATURES_DIR`
split_scps=
for n in $(seq $nj); do
  split_scps="$split_scps $LOCAL_OUTPUT_DIR/noisy_${name}.$n.scp"
done

utils/split_scp.pl $FEATURES_SCP $split_scps || exit 1;

$cmd JOB=1:$nj $LOGS_DIR/append_${name}.JOB.log \
  append-xvectors scp:$XVECTORS_SCP ark:$UTT2SPK \
    scp:$LOCAL_OUTPUT_DIR/noisy_${name}.JOB.scp  \
    ark,scp:$LOCAL_OUTPUT_DIR/feats_$name.JOB.ark,$LOCAL_OUTPUT_DIR/feats_$name.JOB.scp \
  || exit 1;

if [ -f $LOGS_DIR/.error.$name ]; then
  echo "$0: Error appending noisy features with xvectors for $name:"
  tail $LOGS_DIR/append_${name}.1.log
  exit 1;
fi

# concatenate the .scp files together.
for n in $(seq $nj); do
  cat $LOCAL_OUTPUT_DIR/feats_$name.$n.scp || exit 1;
done > $OUTPUT_FEATURES_DIR/feats.scp || exit 1;

echo "$0: Succeeded appending noisy features and xvectors for $name"
