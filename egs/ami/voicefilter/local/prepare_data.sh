#!/usr/bin/env bash

# Copyright 

# Note: this is called by ../run.sh.

# To be run from one directory above this script.

. ./path.sh

#check existing directories
if [ $# -ne 4 ]; then
  echo "Usage: $0 /path/to/noisy/audio /path/to/clean/audio /path/to/noisy/output /path/to/clean/output"
#  echo "e.g. $0 /foo/bar/AMI ihm"
  exit 1;
fi

NOISY_AUDIO_DIR=$1
CLEAN_AUDIO_DIR=$2

#SEGS=data/local/annotations/train.txt
LOCAL_OUTPUT_DIR=data/local/temp
#data/local/ihm/train
NOISY_OUTPUT_DIR=$3
CLEAN_OUTPUT_DIR=$4
#data/ihm/train_orig
mkdir -p $LOCAL_OUTPUT_DIR
mkdir -p $LOCAL_OUTPUT_DIR/noisy
mkdir -p $LOCAL_OUTPUT_DIR/clean

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

# # And transcripts check
# if [ ! -f $SEGS ]; then
#   echo "Error: File $SEGS no found (run ami_text_prep.sh)."
#   exit 1;
# fi

# Prepare noisy part first.
echo "Working with noisy audio first."

# Find all mixture audio files.
find $NOISY_AUDIO_DIR -iname '*.mixture-*.wav' | sort > $LOCAL_OUTPUT_DIR/noisy/wav.flist
n=`cat $LOCAL_OUTPUT_DIR/noisy/wav.flist | wc -l`
echo "In total, $n noisy audio files has been found."

# Make wav.scp file for noisy audio files.
# recording id = AMI_{meeting_id}_H{speaker_1_id}{chunk_id}_{speaker_2_id}{chunk_id}
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
 perl -ne 'split; $_ =~ m/(.*)\..*\-([0-9]{4})\-([0-9]{4})/; print "AMI_$1_H$2_$3 AMI_$1_$2\n"' \
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
sed -e 's?.*/??' -e 's?.wav??' $LOCAL_OUTPUT_DIR/noisy/wav.flist | \
 perl -ne 'split; $_ =~ m/(.*)\..*\-([0-4])([0-9]{3})\-.*/; print "$1/$2/chunks/$1.chunk-$2$3.wav\n"' | \
   awk -v folder=$CLEAN_AUDIO_DIR '{file=$1; printf("%s/%s", folder, file); printf "\n"}' > $LOCAL_OUTPUT_DIR/clean/wav.flist

# Make wav.scp file for clean audio files.
sed -e 's?.*/??' -e 's?.wav??' $LOCAL_OUTPUT_DIR/clean/wav.flist | \
 perl -ne 'split; $_ =~ m/(.*)\..*\-([0-9]{4})/; print "AMI_$1_H$2\n"' | \
  paste - $LOCAL_OUTPUT_DIR/clean/wav.flist > $LOCAL_OUTPUT_DIR/clean/wav2.scp

# [TODO] rename prev file into wav1.scp and keep train part only!
#Keep only  train part of waves
# awk '{print $2}' $dir/segments | sort -u | join - $dir/wav1.scp >  $dir/wav2.scp

#replace path with an appropriate sox command that select single channel only
awk '{print $1" sox -c 1 -t wavpcm -e signed-integer "$2" -t wavpcm - |"}' $LOCAL_OUTPUT_DIR/clean/wav2.scp > $LOCAL_OUTPUT_DIR/clean/wav.scp

# reco2file_and_channel
cat $LOCAL_OUTPUT_DIR/clean/wav.scp \
 | perl -ane '$_ =~ m:^(\S+)(H[0-4][0-9]{3})\s+.*\/([IETB].*)\.wav.*$: || die "bad label $_";
              print "$1$2 $3 A\n"; ' > $LOCAL_OUTPUT_DIR/clean/reco2file_and_channel || exit 1;

sed -e 's?.*/??' -e 's?.wav??' $LOCAL_OUTPUT_DIR/clean/wav.flist | \
 perl -ne 'split; $_ =~ m/(.*)\..*\-([0-9]{4})/; print "AMI_$1_H$2 AMI_$1_$2\n"' | \
   sort -u > $LOCAL_OUTPUT_DIR/clean/utt2spk || exit 1

utils/utt2spk_to_spk2utt.pl <$LOCAL_OUTPUT_DIR/clean/utt2spk >$LOCAL_OUTPUT_DIR/clean/spk2utt || exit 1;

# Copy stuff into its final location
mkdir -p $CLEAN_OUTPUT_DIR
for f in spk2utt utt2spk wav.scp reco2file_and_channel; do
  cp $LOCAL_OUTPUT_DIR/clean/$f $CLEAN_OUTPUT_DIR/$f || exit 1;
done

utils/validate_data_dir.sh --no-feats --no-text $CLEAN_OUTPUT_DIR || exit 1;

# [TODO] get speaker embedding!!!





# # find combined wav audio files only
# find $AUDIO_DIR -iname '*.combined-*.wav' | sort > $LOCAL_OUTPUT_DIR/wav.flist
# n=`cat $LOCAL_OUTPUT_DIR/wav.flist | wc -l`
# echo "In total, $n combined audio files has been found."
# # [ $n -ne 687 ] && \
# #   echo "Warning: expected 687 (168 mtgs x 4 mics + 3 mtgs x 5 mics) data files, found $n"
# [ $n -ne 16 ] && \
#   echo "Warning: expected 16 (4 meetings x 4 speakers) data files, found $n"

# # (1a) Transcriptions preparation
# # here we start with normalised transcriptions, the utt ids follow the convention
# # AMI_MEETING_CHAN_SPK_STIME_ETIME
# # AMI_ES2011a_H00_FEE041_0003415_0003484
# # we use uniq as some (rare) entries are doubled in transcripts

# # awk '{meeting=$1; channel=$2; speaker=$3; stime=$4; etime=$5;
# #  printf("AMI_%s_%s_%s_%07.0f_%07.0f", meeting, channel, speaker, int(100*stime+0.5), int(100*etime+0.5));
# #  for(i=6;i<=NF;i++) printf(" %s", $i); printf "\n"}' $SEGS | sort | uniq > $dir/text

# # # (1b) Make segment files from transcript

# # awk '{
# #        segment=$1;
# #        split(segment,S,"[_]");
# #        audioname=S[1]"_"S[2]"_"S[3]; startf=S[5]; endf=S[6];
# #        print segment " " audioname " " startf*10/1000 " " endf*10/1000 " "
# # }' < $dir/text > $dir/segments

# # (1c) Make wav.scp file.

# sed -e 's?.*/??' -e 's?.wav??' $LOCAL_OUTPUT_DIR/wav.flist | \
#  perl -ne 'split; $_ =~ m/(.*)\..*\-([0-9])/; print "AMI_$1_H0$2\n"' | \
#   paste - $LOCAL_OUTPUT_DIR/wav.flist > $LOCAL_OUTPUT_DIR/wav2.scp

# # [TODO] rename prev file into wav1.scp and keep train part only!
# #Keep only  train part of waves
# # awk '{print $2}' $dir/segments | sort -u | join - $dir/wav1.scp >  $dir/wav2.scp

# #replace path with an appropriate sox command that select single channel only
# awk '{print $1" sox -c 1 -t wavpcm -e signed-integer "$2" -t wavpcm - |"}' $LOCAL_OUTPUT_DIR/wav2.scp > $LOCAL_OUTPUT_DIR/wav.scp

# # (1d) reco2file_and_channel
# cat $LOCAL_OUTPUT_DIR/wav.scp \
#  | perl -ane '$_ =~ m:^(\S+)(H0[0-4])\s+.*\/([IETB].*)\.wav.*$: || die "bad label $_";
#               print "$1$2 $3 A\n"; ' > $LOCAL_OUTPUT_DIR/reco2file_and_channel || exit 1;


# # In this data-prep phase we adapt to the session and speaker [later on we may
# # split into shorter pieces]., We use the 0th, 1st and 3rd underscore-separated
# # fields of the utterance-id as the speaker-id,
# # e.g. 'AMI_EN2001a_IHM_FEO065_0090130_0090775' becomes 'AMI_EN2001a_FEO065'.
# # awk '{print $1}' $dir/segments | \
# #   perl -ane 'chop; @A = split("_", $_); $spkid = join("_", @A[0,1,3]); print "$_ $spkid\n";'  \
# #   >$dir/utt2spk || exit 1;


# # awk '{print $1}' $dir/segments | \
# #   perl -ane '$_ =~ m:^(\S+)([FM][A-Z]{0,2}[0-9]{3}[A-Z]*)(\S+)$: || die "bad label $_";
# #           print "$1$2$3 $1$2\n";' > $dir/utt2spk || exit 1;

# # [TODO] !!!!!! rework after splitting?
# sed -e 's?.*/??' -e 's?.wav??' $LOCAL_OUTPUT_DIR/wav.flist | \
#  perl -ne 'split; $_ =~ m/(.*)\..*\-([0-9])/; print "AMI_$1_H0$2 AMI_$1_$2\n"' \
#    > $LOCAL_OUTPUT_DIR/utt2spk || exit 1
#   #paste - $LOCAL_OUTPUT_DIR/wav.flist > $LOCAL_OUTPUT_DIR/wav2.scp

# utils/utt2spk_to_spk2utt.pl <$LOCAL_OUTPUT_DIR/utt2spk >$LOCAL_OUTPUT_DIR/spk2utt || exit 1;

# # Copy stuff into its final location
# mkdir -p $OUTPUT_DIR
# for f in spk2utt utt2spk wav.scp reco2file_and_channel; do
#   cp $LOCAL_OUTPUT_DIR/$f $OUTPUT_DIR/$f || exit 1;
# done

# utils/validate_data_dir.sh --no-feats --no-text $OUTPUT_DIR || exit 1;

echo AMI data preparation succeeded.
