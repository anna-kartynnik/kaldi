import argparse
import glob
import os
import shutil
import random

import file_utils


def split_meeting_audio_files(clean_audio_folder: str, meeting_id: str, chunk_length: int):
  """
  """
  for speaker_id in os.listdir(os.path.join(clean_audio_folder, meeting_id)):
    speaker_id_int = int(speaker_id)
    combined_folder = file_utils.get_clean_segments_folder(clean_audio_folder, meeting_id, speaker_id_int)
    combined_file_path = file_utils.get_combined_file_path(combined_folder, meeting_id, speaker_id_int)
    chunks_folder = file_utils.get_clean_chunks_folder(clean_audio_folder, meeting_id, speaker_id_int)

    file_utils.recreate_folder(chunks_folder)

    chunk_file_path = file_utils.get_chunk_file_path(chunks_folder, meeting_id, speaker_id_int)

    sox_split_cmd_str = f'sox {combined_file_path} {chunk_file_path} trim 0 {chunk_length} : newfile : restart'

    #'sox -n -b 16 relative_path/output.wav synth 2.25 sine 300 vol 0.5'

    os.system(sox_split_cmd_str)

def create_audio_mixture(mix_output_folder: str, meeting_id: str, speaker_1_chunk: str,
                         speaker_2_chunk: str):
  """
  """
  speaker_1_chunk_number = file_utils.get_speaker_chunk_number(speaker_1_chunk)
  speaker_2_chunk_number = file_utils.get_speaker_chunk_number(speaker_2_chunk)
  mix_file_path = file_utils.get_mix_file_name(
    mix_output_folder, meeting_id, speaker_1_chunk_number, speaker_2_chunk_number
  )

  sox_mix_cmd_str = f'sox -m {speaker_1_chunk} {speaker_2_chunk} {mix_file_path}'

  #print(sox_mix_cmd_str)

  os.system(sox_mix_cmd_str)  

def mix_audio_files(clean_audio_folder: str, meeting_id: str, mix_parent_folder: str):
  """
  """
  print(f'Starting mixing audio for meeting {meeting_id}...')
  number_of_speakers = len(os.listdir(os.path.join(clean_audio_folder, meeting_id)))
  print(f'Found {number_of_speakers} speakers.')

  print('Recreating mixtures folder...')
  mix_output_folder = file_utils.get_mix_folder(mix_parent_folder, meeting_id)
  file_utils.recreate_folder(mix_output_folder)

  print('Mixing audio files...')
  for speaker_id_1 in range(number_of_speakers):
    speaker_1_chunks_folder = file_utils.get_clean_chunks_folder(clean_audio_folder, meeting_id, speaker_id_1)
    speaker_1_chunk_list = glob.glob(os.path.join(speaker_1_chunks_folder, '*.wav'))

    speaker_1_selected_chunks = random.sample(speaker_1_chunk_list, min(len(speaker_1_chunk_list), 10))

    #print('selected 1')
    #print(speaker_1_selected_chunks)

    other_speakers_chunk_list = []
    for speaker_id_2 in range(number_of_speakers):
      if speaker_id_2 == speaker_id_1:
        continue
      speaker_2_chunks_folder = file_utils.get_clean_chunks_folder(clean_audio_folder, meeting_id, speaker_id_2)
      other_speakers_chunk_list.extend(glob.glob(os.path.join(speaker_2_chunks_folder, '*.wav')))
    
    for speaker_1_chunk in speaker_1_selected_chunks:
      speaker_2_chunk = random.choice(other_speakers_chunk_list)

      #print('selected 2')
      #print(speaker_2_chunk)

      create_audio_mixture(mix_output_folder, meeting_id, speaker_1_chunk, speaker_2_chunk)

      # [TODO] how to avoid creating the same mix file but consider both speakers as clean labels?
      #create_audio_mixture(mix_output_folder, meeting_id, speaker_2_chunk, speaker_1_chunk)

    # for speaker_id_2 in range(speaker_id_1 + 1, number_of_speakers):
    #   speaker_2_chunks_folder = file_utils.get_clean_chunks_folder(clean_audio_folder, meeting_id, speaker_id_2)
    #   speaker_2_chunk_list = glob.glob(os.path.join(speaker_2_chunks_folder, '*.wav'))      

    #   for speaker_1_chunk in speaker_1_selected_chunks:
    #     speaker_2_chunk = random.choice(speaker_2_chunk_list)

    #     create_audio_mixture(mix_output_folder, meeting_id, speaker_1_chunk, speaker_2_chunk)

    #     # [TODO] how to avoid creating the same mix file but consider both speakers as clean labels?
    #     create_audio_mixture(mix_output_folder, meeting_id, speaker_2_chunk, speaker_1_chunk)

  mixture_file_list = glob.glob(os.path.join(mix_output_folder, '*.wav'))
  print(f'Finished mixing audio files for the meeting {meeting_id}. \
        {len(mixture_file_list)} new files have been created.'
  )




def main():
  parser = argparse.ArgumentParser()
  parser.add_argument('--clean-audio-folder', default='./../data/clean', type=str)
  # TODO
  #parser.add_argument('--noise-folder', default='./../data/clean', type=str)
  parser.add_argument('--mix-folder', default='./../data/mix', type=str)
  parser.add_argument('--chunk-length', default=3, type=int) # in seconds

  
  # parser.add_argument('--segments-transcript-folder', default='./../annotations/segments', type=str)
  # parser.add_argument('--output-folder', default='./../data/clean', type=str)
  # parser.add_argument('--offset', default=200, type=int)
  # parser.add_argument('--combine', dest='combine', action='store_true')
  # parser.add_argument('--no-combine', dest='combine', action='store_false')

  #parser.set_defaults(combine=True)

  cfg = parser.parse_args()

  # Parallel

  for obj in os.listdir(cfg.clean_audio_folder):
    if os.path.isdir(os.path.join(cfg.clean_audio_folder, obj)):
      meeting_id = obj # {clean_audio_folder}/{meeting_id}/{speaker_id_int}/segments/{meeting_id}.combined-{speaker_id_int}.wav

      # First split into chunks.
      split_meeting_audio_files(cfg.clean_audio_folder, meeting_id, cfg.chunk_length)

      # Then mix different chunks.
      mix_audio_files(cfg.clean_audio_folder, meeting_id, cfg.mix_folder)


if __name__ == '__main__':
    main()