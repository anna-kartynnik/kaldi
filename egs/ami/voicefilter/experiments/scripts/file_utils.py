import glob
import os
import shutil


SEGMENTS_FOLDER_NAME = 'segments'
ENROLLMENT_FOLDER_NAME = 'enrollment'
CHUNKS_FOLDER_NAME = 'chunks'
MIX_FOLDER_NAME = 'mixtures'
COMBINED_FILE_PART = 'combined'
ENROLLMENT_FILE_PART = 'enrollment'
CHUNK_FILE_PART = 'chunk'



def recreate_folder(folder_path: str):
  """
  """
  if os.path.exists(folder_path):
    shutil.rmtree(folder_path)

  os.makedirs(folder_path)


def get_clean_segments_folder(clean_audio_folder: str, meeting_id: str, speaker_id: int):
  """
  """
  return os.path.join(clean_audio_folder, meeting_id, str(speaker_id), SEGMENTS_FOLDER_NAME)

def get_combined_file_path(combined_folder: str, meeting_id: str, speaker_id: int):
  """
  """
  return os.path.join(combined_folder, f'{meeting_id}.{COMBINED_FILE_PART}-{speaker_id}.wav')

def get_enrollment_output_folder(clean_audio_folder: str, meeting_id: str, speaker_id: int):
  """
  """
  return os.path.join(clean_audio_folder, meeting_id, str(speaker_id), ENROLLMENT_FOLDER_NAME)

def get_enrollment_file_path(enrollment_folder: str, meeting_id: str, speaker_id: int):
  """
  """
  return os.path.join(enrollment_folder, f'{meeting_id}.{ENROLLMENT_FILE_PART}-{speaker_id}.wav')

def get_clean_chunks_folder(clean_audio_folder: str, meeting_id: str, speaker_id: int):
  """
  """
  return os.path.join(clean_audio_folder, meeting_id, str(speaker_id), CHUNKS_FOLDER_NAME)

def get_chunk_file_path(chunks_folder: str, meeting_id: str, speaker_id: int):
  """
  """
  return os.path.join(chunks_folder, f'{meeting_id}.{CHUNK_FILE_PART}-{speaker_id}.wav')

def get_speaker_chunk_number(chunk_path: str):
  """
  """
  # Possible chunk file path is `{audio_folder}/{meeting_id}/{speaker_id}/chunks/{meeting_id}.chunk-{speaker_id}{chunk_number}.wav`
  file_basename = os.path.basename(chunk_path)
  file_name = ''.join(file_basename.split('.')[0:-1])
  return file_name.split('-')[-1]

def get_mix_folder(mix_parent_folder: str, meeting_id: str):
  """
  """
  return os.path.join(mix_parent_folder, meeting_id, MIX_FOLDER_NAME)

def get_mix_file_name(mix_output_folder: str, meeting_id: str, speaker_1_chunk_number: str,
                      speaker_2_chunk_number: str):
  """
  """
  return os.path.join(mix_output_folder, f'{meeting_id}.mixture-{speaker_1_chunk_number}-{speaker_2_chunk_number}.wav')