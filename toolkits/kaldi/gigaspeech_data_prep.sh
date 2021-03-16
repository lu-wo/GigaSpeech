#!/usr/bin/env bash
# Copyright 2021  Xiaomi Corporation (Author: Yongqing Wang)
#                 Seasalt AI, Inc (Author: Guoguo Chen)

set -e
stage=3

if [ $# -lt 3 ] || [ $# -gt 4 ]; then
  echo "Usage: $0 <gigaspeech-src> <data-dir> <use-pipe> [<subset-prefix>]"
  echo " e.g.: $0 ~/gigaspeech_data data/ true gigaspeech"
  echo ""
  echo "This script takes the GigaSpeech source directory, and prepares the"
  echo "Kaldi format data directory. When <use-pipe> is true, it decodes the"
  echo "OPUS audio format through a pipe; Otherwise it writes the decoded"
  echo "output to wav files. <subset-prefix> is an optional prefix for Kaldi"
  echo "data directories."
  exit 1
fi

gigaspeech_src=$1
data_dir=$2
use_pipe=$3
prefix=
if [ $# -eq 4 ]; then
  prefix=${3}_
fi

garbage_tags="<SIL> <MUSIC> <NOISE> <OTHER>"
punctuations_tags="<COMMA> <EXCLAMATIONPOINT> <PERIOD> <QUESTIONMARK>"

declare -A subsets
subsets=([train]="XL" [dev]="DEV" [test]="TEST")

corpus_dir=$data_dir/${prefix}corpus/
if [ $stage -le 1 ]; then
  echo "$0: Analyze meta into $corpus_dir"
  # Sanity check.
  [ ! -f $gigaspeech_src/GigaSpeech.json ] &&\
    echo "$0: Please download $gigaspeech_src/GigaSpeech.json!" && exit 1
  [ ! -d $gigaspeech_src/audio ] &&\
    echo "$0: Please download $gigaspeech_src/audio!" && exit 1

  [ ! -d $corpus_dir ] && mkdir -p $corpus_dir

  # Files to be created:
  # wav.scp utt2spk text and segments utt2dur reco2dur spk2utt
  if [ "$use_pipe" = true ]; then
    python3 toolkits/kaldi/extract_corpus_for_kaldi.py \
      --pipe-format $gigaspeech_src/GigaSpeech.json $corpus_dir || exit 1
  else
    python3 toolkits/kaldi/extract_corpus_for_kaldi.py \
      $gigaspeech_src/GigaSpeech.json $corpus_dir || exit 1
    toolkits/kaldi/opus_to_wav.sh --grid-engine $corpus_dir/wav.scp || exit 1
  fi
  utt2spk=$corpus_dir/utt2spk
  spk2utt=$corpus_dir/spk2utt
  utt2spk_to_spk2utt.pl <$utt2spk >$spk2utt ||\
    (echo "$0: Error: utt2spk to spk2utt" && exit 1)
fi

if [ $stage -le 2 ]; then
  echo "$0: Filter $corpus_dir/text"
  # Delete utterances with garbage meta tags
  for tag in $garbage_tags; do
    sed -i "/${tag}/d" $corpus_dir/text
  done

  # Delete punctuations in utterances
  for tag in $punctuations_tags; do
    sed -i "s/${tag}//g" $corpus_dir/text
  done

  # Ensure space only appears once and utt is seprated with others by '\t'
  sed -i 's/\t/ /g' $corpus_dir/text
  sed -i 's/[ ][ ]*/ /g' $corpus_dir/text
  sed -i 's/ /\t/' $corpus_dir/text
fi

if [ $stage -le 3 ]; then
  echo "$0: Split data to train, dev and test"
  # Split data to train, dev and test.
  [ ! -f $corpus_dir/utt2subsets ] &&\
    echo "$0: Error: No such file $corpus_dir/utt2subsets!" && exit 1
  for subset in ${!subsets[*]}; do
    [ ! -d $data_dir/${prefix}$subset ] && mkdir -p $data_dir/${prefix}$subset
    tag=${subsets[$subset]}
    grep "{$tag}" $corpus_dir/utt2subsets |\
      subset_data_dir.sh --utt-list - \
      $corpus_dir $data_dir/${prefix}$subset || exit 1
  done
fi

echo "$0: Done"
