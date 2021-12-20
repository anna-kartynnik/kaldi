#!/usr/bin/env bash

# hk3129: Authored by me (modeled after Kaldi feature extraction scripts).

nj=4
cmd=run.pl
mfcc_config=conf/mfcc.conf
compress=true

echo "$0 $@"  # Print the command line for logging.

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# -lt 1 ] || [ $# -gt 3 ]; then
  cat >&2 <<EOF
Usage: $0 [options] <data-dir> [<log-dir> [<mfcc-dir>] ]
 e.g.: $0 data/train
Note: <log-dir> defaults to <data-dir>/log, and
      <mfcc-dir> defaults to <data-dir>/data.
Options:
  --mfcc-config <config-file>          # config passed to compute-mfcc-feats.
  --nj <nj>                            # number of parallel jobs.
  --cmd <run.pl|queue.pl <queue opts>> # how to run jobs.
EOF
   exit 1;
fi

data=$1

mfcc_params=""
while read -r line; do
  [[ "$line" =~ ^#.*$ ]] && continue
  linearray=($line)
  if [[ ${linearray[0]} == --num-mel-bins* ]] || [[ ${linearray[0]} == --num-ceps* ]] || [[ ${linearray[0]} == --cepstral-lifter* ]]; then
    mfcc_params="${linearray[0]} $mfcc_params" 
  fi
done < "$mfcc_config"
echo "$mfcc_params"


logdir=$data/log
mfccdir=$data/data

# Make $mfccdir an absolute pathname.
mfccdir=`perl -e '($dir,$pwd)= @ARGV; if($dir!~m:^/:) { $dir = "$pwd/$dir"; } print $dir; ' $mfccdir ${PWD}`

# Use "name" as part of name of the archive.
name=`basename $data`

mkdir -p $mfccdir || exit 1;
mkdir -p $logdir || exit 1;

if [ -f $data/feats.scp ]; then
  mkdir -p $data/.backup
  echo "$0: moving $data/feats.scp to $data/.backup"
  mv $data/feats.scp $data/.backup
fi

fbank_scp=$data/feats_fbank.scp

required="$fbank_scp $mfcc_config"

for f in $required; do
  if [ ! -f $f ]; then
    echo "$0: no such file $f"
    exit 1;
  fi
done

utils/validate_data_dir.sh --no-text --no-feats $data || exit 1;

for n in $(seq $nj); do
  utils/create_data_link.pl $mfccdir/raw_mfcc_$name.$n.ark
done

echo "$0: [info]: no segments file exists: assuming feats_fbank.scp indexed by utterance."
split_scps=
for n in $(seq $nj); do
  split_scps="$split_scps $mfccdir/raw_fbank_${name}.$n.scp"
done

utils/split_scp.pl $fbank_scp $split_scps || exit 1;


$cmd JOB=1:$nj $logdir/fbank_to_mfcc_${name}.JOB.log \
  fbank-to-mfcc --verbose=2 $mfcc_params scp,p:$mfccdir/raw_fbank_${name}.JOB.scp ark:- \| \
  copy-feats --compress=$compress ark:- \
    ark,scp:$mfccdir/raw_mfcc_$name.JOB.ark,$mfccdir/raw_mfcc_$name.JOB.scp \
    || exit 1;


if [ -f $logdir/.error.$name ]; then
  echo "$0: Error producing MFCC features for $name:"
  tail $logdir/make_mfcc_${name}.1.log
  exit 1;
fi

for n in $(seq $nj); do
  cat $mfccdir/raw_mfcc_$name.$n.scp || exit 1
done > $data/feats.scp || exit 1

rm $logdir/feats_fbank_${name}.*.scp  $logdir/segments.* 2>/dev/null

nf=$(wc -l < $data/feats.scp)
nu=$(wc -l < $data/utt2spk)
if [ $nf -ne $nu ]; then
  echo "$0: It seems not all of the feature files were successfully procesed" \
       "($nf != $nu); consider using utils/fix_data_dir.sh $data"
fi

if (( nf < nu - nu/20 )); then
  echo "$0: Less than 95% the features were successfully generated."\
       "Probably a serious error."
  exit 1
fi

echo "$0: Succeeded creating MFCC features from Fbank features for $name"
