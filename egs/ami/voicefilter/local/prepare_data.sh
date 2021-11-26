#!/usr/bin/env bash

# Copyright 

# Note: this is called by ../run.sh.

# To be run from one directory above this script.

. ./path.sh

# [TODO] check existing directories
if [ $# -ne 6 ]; then
  echo "Usage: $0 /path/to/noisy/audio /path/to/clean/audio /path/to/enrollment/audio /path/to/noisy/output /path/to/clean/output /path/to/enrollment/output"
#  echo "e.g. $0 /foo/bar/AMI ihm"
  exit 1;
fi

echo "$0 $@"  # Print the command line for logging.

NOISY_AUDIO_DIR=$1
CLEAN_AUDIO_DIR=$2
ENROLLMENT_AUDIO_DIR=$3

#SEGS=data/local/annotations/train.txt
LOCAL_OUTPUT_DIR=data/local/temp
#data/local/ihm/train
NOISY_OUTPUT_DIR=$4
CLEAN_OUTPUT_DIR=$5
ENROLLMENT_OUTPUT_DIR=$6

#data/ihm/train_orig
mkdir -p $LOCAL_OUTPUT_DIR
mkdir -p $LOCAL_OUTPUT_DIR/noisy
mkdir -p $LOCAL_OUTPUT_DIR/clean
mkdir -p $LOCAL_OUTPUT_DIR/enrollment

# Noisy audio data directory check
if [ ! -d $NOISY_AUDIO_DIR ]; then
  echo "Error: $NOISY_AUDIO_DIR directory does not exists."
  exit 1;
fi

# Clean audio data directory check
if [ ! -d $CLEAN_AUDIO_DIR ]; then
  echo "Error: $CLEAN_AUDIO_DIR directory does not exists."
  exit 1;
fi

# Enrollment audio data directory check
if [ ! -d $ENROLLMENT_AUDIO_DIR ]; then
  echo "Error: $ENROLLMENT_AUDIO_DIR directory does not exists."
  exit 1;
fi

# Prepare noisy part first.
echo "Working with noisy audio first."

# Find all mixture audio files.
find $NOISY_AUDIO_DIR -iname '*.mixture-*.wav' | sort > $LOCAL_OUTPUT_DIR/noisy/wav.flist
n=`cat $LOCAL_OUTPUT_DIR/noisy/wav.flist | wc -l`
echo "In total, $n noisy audio files has been found."

# Make wav.scp file for noisy audio files.
# recording_id = AMI_{meeting_id}_H{speaker_1_id}{chunk_id}_{speaker_2_id}{chunk_id}
sed -e 's?.*/??' -e 's?.wav??' $LOCAL_OUTPUT_DIR/noisy/wav.flist | \
 perl -ne 'split; $_ =~ m/(.*)\..*\-([0-9]{4})\-([0-9]{4})/; print "AMI_$1_H$2_$3\n"' | \
  paste - $LOCAL_OUTPUT_DIR/noisy/wav.flist > $LOCAL_OUTPUT_DIR/noisy/wav2.scp

# [TODO] rename prev file into wav1.scp and keep train part only!
#Keep only  train part of waves
# awk '{print $2}' $dir/segments | sort -u | join - $dir/wav1.scp >  $dir/wav2.scp

#replace path with an appropriate sox command that select single channel only
awk '{print $1" sox -c 1 -t wavpcm -e signed-integer "$2" -t wavpcm - |"}' $LOCAL_OUTPUT_DIR/noisy/wav2.scp > $LOCAL_OUTPUT_DIR/noisy/wav.scp

# reco2file_and_channel
cat $LOCAL_OUTPUT_DIR/noisy/wav.scp \
 | perl -ane '$_ =~ m:^(\S+)(H[0-4][0-9]{3}_[0-4][0-9]{3})\s+.*\/([IETB].*)\.wav.*$: || die "bad label $_";
              print "$1$2 $3 A\n"; ' > $LOCAL_OUTPUT_DIR/noisy/reco2file_and_channel || exit 1;

sed -e 's?.*/??' -e 's?.wav??' $LOCAL_OUTPUT_DIR/noisy/wav.flist | \
 perl -ne 'split; $_ =~ m/(.*)\..*\-([0-4])([0-9]{3})\-([0-9]{4})/; print "AMI_$1_H$2$3_$4 AMI_$1_$2\n"' \
   > $LOCAL_OUTPUT_DIR/noisy/utt2spk || exit 1

utils/utt2spk_to_spk2utt.pl <$LOCAL_OUTPUT_DIR/noisy/utt2spk >$LOCAL_OUTPUT_DIR/noisy/spk2utt || exit 1;

# Copy stuff into its final location
mkdir -p $NOISY_OUTPUT_DIR
for f in spk2utt utt2spk wav.scp reco2file_and_channel; do
  cp $LOCAL_OUTPUT_DIR/noisy/$f $NOISY_OUTPUT_DIR/$f || exit 1;
done

utils/validate_data_dir.sh --no-feats --no-text $NOISY_OUTPUT_DIR || exit 1;


# Now work with clean data.
echo "Working with clean data."

# Create wav.flist corresponding to the noisy files.
# a list of e.g. experiments/data/clean/ES2002a/1/chunks/ES2002a.chunk-1001.wav
#sed -e 's?.*/??' -e 's?.wav??' $LOCAL_OUTPUT_DIR/noisy/wav.scp | \
# perl -ne 'split; $_ =~ m/(.*)\..*\-([0-4])([0-9]{3})\-.*/; print "$1/$2/chunks/$1.chunk-$2$3.wav\n"' | \
#   awk -v folder=$CLEAN_AUDIO_DIR '{file=$1; printf("%s/%s", folder, file); printf "\n"}' > $LOCAL_OUTPUT_DIR/clean/wav.flist

# Make wav.scp file for clean audio files.
#sed -e 's?.*/??' -e 's?.wav??' $LOCAL_OUTPUT_DIR/clean/wav.flist | \
# perl -ne 'split; $_ =~ m/(.*)\..*\-([0-9]{4})/; print "AMI_$1_H$2\n"' | \
#  paste - $LOCAL_OUTPUT_DIR/clean/wav.flist > $LOCAL_OUTPUT_DIR/clean/wav2.scp
awk '{print $1}' $LOCAL_OUTPUT_DIR/noisy/wav2.scp > $LOCAL_OUTPUT_DIR/clean/uttids
awk '{print $1}' $LOCAL_OUTPUT_DIR/noisy/wav2.scp | \
# $1 = meeting_id $2 = speaker1_id $3 = chunk1_id $4 = speaker2_id $5 = chunk2_id
  perl -ne 'split; $_ =~ m/AMI_(.*)_H([0-4])([0-9]{3})_([0-4])([0-9]{3})/; print "/$1/$2/chunks/$1.chunk-$2$3.wav\n"' | \
  awk -v clean_folder=$CLEAN_AUDIO_DIR '{print clean_folder $1}' - | \
  paste $LOCAL_OUTPUT_DIR/clean/uttids - > $LOCAL_OUTPUT_DIR/clean/wav2.scp

# [TODO] rename prev file into wav1.scp and keep train part only!
#Keep only  train part of waves
# awk '{print $2}' $dir/segments | sort -u | join - $dir/wav1.scp >  $dir/wav2.scp

#replace path with an appropriate sox command that select single channel only
awk '{print $1" sox -c 1 -t wavpcm -e signed-integer "$2" -t wavpcm - |"}' $LOCAL_OUTPUT_DIR/clean/wav2.scp > $LOCAL_OUTPUT_DIR/clean/wav.scp

# reco2file_and_channel
cat $LOCAL_OUTPUT_DIR/clean/wav.scp \
 | perl -ane '$_ =~ m:^(\S+)(H[0-4][0-9]{3}_[0-4][0-9]{3})\s+.*\/([IETB].*)\.wav.*$: || die "bad label $_";
              print "$1$2 $3 A\n"; ' > $LOCAL_OUTPUT_DIR/clean/reco2file_and_channel || exit 1;


# cat $LOCAL_OUTPUT_DIR/clean/wav.scp \
#  | perl -ane '$_ =~ m:^(\S+)(H[0-4][0-9]{3})\s+.*\/([IETB].*)\.wav.*$: || die "bad label $_";
#               print "$1$2 $3 A\n"; ' > $LOCAL_OUTPUT_DIR/clean/reco2file_and_channel || exit 1;

# awk '{print $1}' $LOCAL_OUTPUT_DIR/clean/wav.scp | \
#  perl -ne 'split; $_ =~ m/AMI_(.*)_H([0-4])([0-9]{3})_([0-9]{4})/; print "AMI_$1_H$2$3_$4 AMI_$1_$2\n"' | \
#    sort -u > $LOCAL_OUTPUT_DIR/clean/utt2spk || exit 1


#  #sed -e 's?.*/??' -e 's?.wav??' $LOCAL_OUTPUT_DIR/noisy/wav.flist | \
#  # perl -ne 'split; $_ =~ m/(.*)\..*\-([0-4])([0-9]{3})\-([0-9]{4})/; print "AMI_$1_H$2$3_$4 AMI_$1_$2\n"' \
#  #   > $LOCAL_OUTPUT_DIR/noisy/utt2spk || exit 1

# utils/utt2spk_to_spk2utt.pl <$LOCAL_OUTPUT_DIR/clean/utt2spk >$LOCAL_OUTPUT_DIR/clean/spk2utt || exit 1;

# utt2spk and spk2utt are the same for all audio types.
for f in spk2utt utt2spk; do
  cp $LOCAL_OUTPUT_DIR/noisy/$f $LOCAL_OUTPUT_DIR/clean/$f || exit 1;
done

# Copy stuff into its final location
mkdir -p $CLEAN_OUTPUT_DIR
for f in spk2utt utt2spk wav.scp reco2file_and_channel; do
  cp $LOCAL_OUTPUT_DIR/clean/$f $CLEAN_OUTPUT_DIR/$f || exit 1;
done

utils/validate_data_dir.sh --no-feats --no-text $CLEAN_OUTPUT_DIR || exit 1;





# Now prepare enrollment data.
echo "Working with enrollment data."

# Provide enrollments for all utterances. utt-id looks like 'AMI_ES2002a_H0001_3003'.
awk '{print $1}' $LOCAL_OUTPUT_DIR/clean/uttids | \
  perl -ne 'split; $_ =~ m/AMI_(.*)_H([0-4])([0-9]{3})_([0-9]{4})/; print "/$1/$2/enrollment/$1.enrollment-$2.wav\n"' | \
  awk -v folder=$ENROLLMENT_AUDIO_DIR '{print folder $1}' - | \
  paste $LOCAL_OUTPUT_DIR/clean/uttids - > $LOCAL_OUTPUT_DIR/enrollment/wav2.scp

#replace path with an appropriate sox command that select single channel only
awk '{print $1" sox -c 1 -t wavpcm -e signed-integer "$2" -t wavpcm - |"}' $LOCAL_OUTPUT_DIR/enrollment/wav2.scp > $LOCAL_OUTPUT_DIR/enrollment/wav.scp

# reco2file_and_channel
cat $LOCAL_OUTPUT_DIR/enrollment/wav.scp \
 | perl -ane '$_ =~ m:^(\S+)(H[0-4][0-9]{3}_[0-4][0-9]{3})\s+.*\/([IETB].*)\.wav.*$: || die "bad label $_";
              print "$1$2 $3 A\n"; ' > $LOCAL_OUTPUT_DIR/enrollment/reco2file_and_channel || exit 1;

# awk '{print $1}' $LOCAL_OUTPUT_DIR/enrollment/wav.scp | \
#  perl -ne 'split; $_ =~ m/AMI_(.*)_([0-4])/; print "AMI_$1_$2 AMI_$1_$2\n"' | \
#    sort -u > $LOCAL_OUTPUT_DIR/enrollment/utt2spk || exit 1

# utils/utt2spk_to_spk2utt.pl <$LOCAL_OUTPUT_DIR/enrollment/utt2spk >$LOCAL_OUTPUT_DIR/enrollment/spk2utt || exit 1;

# utt2spk and spk2utt are the same for all audio types.
for f in spk2utt utt2spk; do
  cp $LOCAL_OUTPUT_DIR/noisy/$f $LOCAL_OUTPUT_DIR/enrollment/$f || exit 1;
done

# Copy stuff into its final location
mkdir -p $ENROLLMENT_OUTPUT_DIR
for f in spk2utt utt2spk wav.scp reco2file_and_channel; do
  cp $LOCAL_OUTPUT_DIR/enrollment/$f $ENROLLMENT_OUTPUT_DIR/$f || exit 1;
done

utils/validate_data_dir.sh --no-feats --no-text $ENROLLMENT_OUTPUT_DIR || exit 1;

rm -r $LOCAL_OUTPUT_DIR

echo AMI data preparation succeeded.
