#!/usr/bin/env python

import argparse
import glob
import os
import shutil
import re
import random
import multiprocessing as mp
from tqdm import tqdm
import time

import xml.etree.ElementTree as ET

from pydub import AudioSegment

import file_utils

# XML constants
XML_NAMESPACES = {'nite': 'http://nite.sourceforge.net/'}
SEGMENT_TAG_NAME = 'segment'
SEGMENT_CHILD_HREF_ATTRIBUTE_NAME = 'href'
SEGMENT_TRANSCRIBER_START_TAG_NAME = 'transcriber_start'
SEGMENT_TRANSCRIBER_END_TAG_NAME = 'transcriber_end'
WORD_STARTTIME_TAG_NAME = 'starttime'
WORD_ENDTIME_TAG_NAME = 'endtime'


class SegmentPoint(object):
  """Represents a segment point (start or end)."""
  def __init__(self, speaker_id: str, point: int, start_time: int, end_time: int, is_start: bool):
    """
    Takes
      - speaker_id - a speaker's id (e.g. 'A')
      - point - either start or end time of the segment (in ms)
      - start_time - start time of the segment (in ms)
      - end_time - end time of the segment (in ms)  
    """
    self.speaker_id = speaker_id
    self.point = point
    self.start_time = start_time
    self.end_time = end_time
    self.is_start = is_start

  def is_same_segment(self, other):
    """"""
    return (
      self.speaker_id == other.speaker_id and 
      self.start_time == other.start_time and 
      self.end_time == other.end_time
    )

  def __lt__(self, other):
    """"""
    if self.point == other.point:
      if self.end_time == other.start_time:
        return True
      elif self.start_time == other.end_time:
        return False
    else:
      return self.point < other.point

  def __str__(self):
    return f'{self.speaker_id}:{self.start_time}'

  def __repr__(self):
    return str(self)


def convert_speaker_id_int_to_str(speaker_id_int: int) -> str:
  """"""
  return chr(ord('A') + speaker_id_int)

def convert_speaker_id_str_to_int(speaker_id_str: str) -> int:
  """"""
  return ord(speaker_id_str) - ord('A')

def combine_wavs(wavs):
  """
  """
  combined_wav = wavs[0]

  for wav in wavs[1:]:
    combined_wav += wav

  return combined_wav  

def concatenate_audio_files(output_folder: str, meeting_id: str, speaker_id: int, chunk_length: int):
  """
  """
  output_files_folder = file_utils.get_clean_segments_folder(output_folder, meeting_id, speaker_id)
  combined_file_path = file_utils.get_combined_file_path(output_files_folder, meeting_id, speaker_id)

  if os.path.exists(combined_file_path):
    os.remove(combined_file_path)

  speaker_segment_audio_files = glob.glob(
    f'{output_files_folder}/*.wav'
  )
  print(f'{len(speaker_segment_audio_files)} audio files found for speaker {speaker_id}, meeting {meeting_id}.')

  if len(speaker_segment_audio_files) == 0:
    print(f'There are no audio segments for speaker {speaker_id}, do nothing')
    return

  # [TODO] sort the segments first?
  speaker_wavs = [AudioSegment.from_wav(wav_path) for wav_path in speaker_segment_audio_files]
  # speaker_combined_wav = speaker_wavs[0]

  # for speaker_wav in speaker_wavs[1:]:
  #   speaker_combined_wav = speaker_combined_wav.append(speaker_wav)

  speaker_combined_wav = combine_wavs(speaker_wavs)

  print(f'Combined audio length: {speaker_combined_wav.duration_seconds}')
  combined_length_ms = int(speaker_combined_wav.duration_seconds * 1000)
  chunk_length_ms = chunk_length * 1000
  required_length_ms = (combined_length_ms // chunk_length_ms + 1) * chunk_length_ms
  padding_length_ms = required_length_ms - combined_length_ms
  print(f'Trying to pad to have length: {required_length_ms}')
  #padding_length_ms = int(padding_length * 1000)
  print(f'Padding length: {padding_length_ms}')
  left_padding_length_ms = padding_length_ms // 2
  right_padding_length_ms = padding_length_ms - left_padding_length_ms + 1000  # we will trim it later

  padded_speaker_combined_wav = combine_wavs([
    AudioSegment.silent(duration=left_padding_length_ms),
    speaker_combined_wav,
    AudioSegment.silent(duration=right_padding_length_ms)
  ])[:required_length_ms]
  print(f'The final combined audio length: {padded_speaker_combined_wav.duration_seconds}')

  padded_speaker_combined_wav.export(combined_file_path, format='wav')


def get_segment_start_end_time(segment_xml, words_xml_root):
  """
  Uses <segment> element to find start and end time of speaking.
  Tries to use the associated with this segment words and their times.
  If they are not available for some reason, uses the times saved with
  this segment element.
  Returns `None` instead of times if the element's structure is not expected.
  """
  words_href = None
  for segment_child in segment_xml:
    # Should be only one child?
    if words_href is not None:
      print(f'[WARNING] There are more than one child in the segment {segment_xml.attrib}')
      break
    words_href = segment_child.attrib[SEGMENT_CHILD_HREF_ATTRIBUTE_NAME]

  start_time, end_time = None, None
  if words_href is not None:
    word_ids = re.findall('id\((.+?)\)', words_href)
    if len(word_ids) == 0 or len(word_ids) > 2:
      print(f'[WARNING] Unexpected number of word ids in the segment {segment_xml.attrib}')
    else:
      start_word_id = word_ids[0]
      end_word_id = word_ids[0] # In case when there is only one word.
      if len(word_ids) == 2:
        end_word_id = word_ids[1]

      start_word_element = words_xml_root.find(f"./*[@nite:id='{start_word_id}']", XML_NAMESPACES) 
      end_word_element = words_xml_root.find(f"./*[@nite:id='{end_word_id}']", XML_NAMESPACES)
      if start_word_element is None:
        print(f'[WARNING] No start word in the segment {segment_xml.attrib}')
      elif end_word_element is None:
        print(f'[WARNING] No end word in the segment {segment_xml.attrib}')
      elif WORD_STARTTIME_TAG_NAME not in start_word_element.attrib or WORD_ENDTIME_TAG_NAME not in end_word_element.attrib:
        print(f'[WARNING] Invalid time tags in the words associated with the segment {segment_xml.attrib}')
      else:
        start_time = start_word_element.attrib[WORD_STARTTIME_TAG_NAME]
        end_time = end_word_element.attrib[WORD_ENDTIME_TAG_NAME]


  # Debugging, remove?
  # if start_time != segment_xml.attrib[SEGMENT_TRANSCRIBER_START_TAG_NAME] or end_time != segment_xml.attrib[SEGMENT_TRANSCRIBER_END_TAG_NAME]:
  #   print(f'found in words: {start_time} and {end_time}')
  #   print(f'segment times: {segment_xml.attrib[SEGMENT_TRANSCRIBER_START_TAG_NAME]} and {segment_xml.attrib[SEGMENT_TRANSCRIBER_END_TAG_NAME]}')

  if start_time is None or end_time is None:
    # Try to use segment element time attributes instead.
    if SEGMENT_TRANSCRIBER_START_TAG_NAME not in segment_xml.attrib or \
      SEGMENT_TRANSCRIBER_END_TAG_NAME not in segment_xml.attrib:
      print(f'[WARNING] Found <segment> element without "transcriber_start" or "transcriber_end" attributes')
    else:
      start_time = segment_xml.attrib[SEGMENT_TRANSCRIBER_START_TAG_NAME]
      end_time = segment_xml.attrib[SEGMENT_TRANSCRIBER_END_TAG_NAME]

  if start_time is None or end_time is None:
    return None, None
  else:
    # Time is stored in seconds. We convert it to milliseconds.
    start = int(float(start_time) * 1000)
    end = int(float(end_time) * 1000)
    return start, end


def extract_duration_from_segment_file(file_path: str):
  """
  """
  _, file_name_ext = os.path.split(file_path)
  file_name = file_name_ext.split('.')[0]
  start, end = file_name.split('-')
  return int(end) - int(start)

def save_enrollment(output_folder: str, meeting_id: str, number_of_speakers: int, duration_threshold: int):
  """
  """
  # Should be run before concatenation code since the code assumes the output folder consists
  # of only individual segment files.
  for speaker_id_int in range(number_of_speakers):
    audio_segment_files_folder = file_utils.get_clean_segments_folder(output_folder, meeting_id, speaker_id_int)
    audio_segment_files = glob.glob(os.path.join(audio_segment_files_folder, '*.wav'))

    filtered_segment_files = list(
      filter(
        lambda segment_file_name: (
            extract_duration_from_segment_file(segment_file_name) >= duration_threshold and
            extract_duration_from_segment_file(segment_file_name) <= 10000
          ),
        audio_segment_files
      )
    )

    if len(filtered_segment_files) == 0:
      print(f'There are no segments for speaker {speaker_id_int}')
      # [TODO] not continue? throw something?
      continue

    # Choose a random audio segment as an enrollment file.
    random_enrollment_file_name = random.choice(filtered_segment_files)
    print(f'Enrollment file has been chosen {random_enrollment_file_name}, its duration is {extract_duration_from_segment_file(random_enrollment_file_name)} (ms).')

    # Move the enrollment file into a separate folder.
    enrollment_folder = file_utils.get_enrollment_output_folder(
      output_folder,
      meeting_id,
      speaker_id_int
    )
    print(enrollment_folder)
    if not os.path.exists(enrollment_folder):
      os.makedirs(enrollment_folder)

    os.rename(
      random_enrollment_file_name,
      file_utils.get_enrollment_file_path(enrollment_folder, meeting_id, speaker_id_int)
      # os.path.join(
      #   enrollment_folder,
      #   f'{meeting_id}.{DEFAULT_ENROLLMENT_FILE_NAME}-{speaker_id_int}.wav'
      # )
    )
    print('The enrollment file has been successfully moved into the separate folder.')

def extract_clean_audio(meeting_id: str, audio_folder: str,
                        annotations_folder: str, output_folder: str,
                        offset: int, enrollment_duration_threshold: int,
                        chunk_length: int, combine: bool):
  """
  Gets a file path where the recordings from individual headsets are located.
  Returns audio segments of individual speakers without overlapping with other speakers.
  """
  assert meeting_id, 'Meeting id needs to be specified'
  assert audio_folder, 'The folder where audio recordings are located needs to be specified'
  assert annotations_folder, 'The folder where transcript files are located needs to be specified'

  print(f'Starting clean audio extraction: \
    meeting id = {meeting_id}, audio folder = {audio_folder}, annotations folder = {annotations_folder}...')

  if audio_folder.endswith('/'):
    audio_folder = audio_folder[:-1]

  if annotations_folder.endswith('/'):
    annotations_folder = annotations_folder[:-1]

  transcript_segment_files = glob.glob(os.path.join(annotations_folder, 'segments', f'{meeting_id}.*.segments.xml'))
  number_of_speakers = len(transcript_segment_files)

  print(f'Found {number_of_speakers} speakers in the transcript segments')

  print('Gathering segments...')
  segment_points = []
  for speaker_id_int in range(number_of_speakers):
    speaker_id_str = convert_speaker_id_int_to_str(speaker_id_int)

    segments_file_path = os.path.join(annotations_folder, 'segments', f'{meeting_id}.{speaker_id_str}.segments.xml')
    segments_xml_root = ET.parse(segments_file_path).getroot()

    words_file_path = os.path.join(annotations_folder, 'words', f'{meeting_id}.{speaker_id_str}.words.xml')
    words_xml_root = ET.parse(words_file_path).getroot()

    for segment_xml in segments_xml_root:
      if segment_xml.tag != SEGMENT_TAG_NAME:
        # Just ignore.
        continue

      start, end = get_segment_start_end_time(segment_xml, words_xml_root)
      if start is None or end is None:
        # Ignore.
        continue

      segment_points.append(SegmentPoint(
        speaker_id_str,
        start + offset,
        start,
        end,
        True
      ))

      segment_points.append(SegmentPoint(
        speaker_id_str,
        end - offset,
        start,
        end,
        False
      ))

  print(f'All the segments for the {meeting_id} meeting have been successfully collected. Sorting...')
  #print(segment_points)
  segment_points.sort()

  #print(segment_points)

  segments_without_overlapping = []
  number_of_overlapping_segments = 0
  for i in range(len(segment_points)):
    segment_point = segment_points[i]
    prev_segment_point = segment_points[i - 1] if i > 0 else None
    if segment_point.is_start:
      number_of_overlapping_segments += 1
    else:
      if number_of_overlapping_segments == 1 and (
          prev_segment_point is None or prev_segment_point.is_same_segment(segment_point)
        ):
        segments_without_overlapping.append((
          segment_point.speaker_id,
          segment_point.start_time,
          segment_point.end_time
        ))
      number_of_overlapping_segments -= 1

  print(f'{len(segments_without_overlapping)} segments without overlapping has been found.')

  segments_per_speaker = [0] * number_of_speakers
  max_segment_per_speaker = [0] * number_of_speakers

  speaker_original_audio_files = [None] * number_of_speakers
  for speaker_id_int in range(number_of_speakers):
    audio_file_path = os.path.join(audio_folder, f'{meeting_id}.Headset-{speaker_id_int}.wav')   # e.g. ES2002a.Headset-1.wav
    speaker_original_audio_files[speaker_id_int] = AudioSegment.from_wav(audio_file_path)

  for segment in segments_without_overlapping:
    speaker_id_int = convert_speaker_id_str_to_int(segment[0])
    segments_per_speaker[speaker_id_int] += 1
    start = segment[1]
    end = segment[2]

    # TODO remove?
    if end - start > max_segment_per_speaker[speaker_id_int]:
      max_segment_per_speaker[speaker_id_int] = end - start


    # audio_file_path = os.path.join(audio_folder, f'{meeting_id}.Headset-{speaker_id_int}.wav')   # e.g. ES2002a.Headset-1.wav
   
    # whole_audio = AudioSegment.from_wav(audio_file_path) 
    # audio_segment = whole_audio[start:end]

    audio_segment = speaker_original_audio_files[speaker_id_int][start:end]

    output_files_folder = file_utils.get_clean_segments_folder(
      output_folder,
      meeting_id,
      speaker_id_int
    )
    if not os.path.exists(output_files_folder):
      os.makedirs(output_files_folder)

    audio_segment.export(os.path.join(output_files_folder, f'{start}-{end}.wav'), format='wav')

  print(f'Clean audio segments have been successfully extracted. Segments per speaker: {segments_per_speaker}')
  print(f'Max segment length per speaker: {max_segment_per_speaker}')

  # Choose enrollment segment.
  save_enrollment(output_folder, meeting_id, number_of_speakers, enrollment_duration_threshold)

  print(f'combine {combine}')
  if combine:
    print('Concatenating segments into one audio file.')
    for speaker_id_int in range(number_of_speakers):
      concatenate_audio_files(
        output_folder,
        meeting_id,
        speaker_id_int,
        chunk_length
      )

    print('Concatenation has been successfully performed.')


@file_utils.logger_decorator
def process_meeting_folder(logs_folder: str, meeting_id: str, audio_folder: str, output_folder: str,
                           annotations_folder: str, offset: int, enrollment_duration_threshold: int,
                           chunk_length: int, combine: bool):
  """
  """
  try:
    meeting_folder = os.path.join(audio_folder, meeting_id)
    if os.path.isdir(meeting_folder):
      # Clean the previous extraction if any.
      meeting_output_folder = os.path.join(output_folder, meeting_id)
      if os.path.exists(meeting_output_folder):
        shutil.rmtree(meeting_output_folder)

      extract_clean_audio(
        meeting_id,
        os.path.join(meeting_folder, 'audio'),
        annotations_folder,
        output_folder,
        offset,
        enrollment_duration_threshold,
        chunk_length,
        combine
      )
    return 1
  except Exception as e:
    print(f'Error occurred: {e}')
    return 0

number_of_processed_meetings = 0
def collect_extraction_result(result):
  global number_of_processed_meetings
  number_of_processed_meetings += result


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument('--audio-folder', default='./../experiments/amicorpus', type=str)
  parser.add_argument('--annotations-folder', default='./../experiments/annotations', type=str)
  parser.add_argument('--output-folder', default='./../data/processed/clean', type=str)
  parser.add_argument('--logs-folder', default='./../logs/extraction', type=str)
  parser.add_argument('--offset', default=100, type=int)
  parser.add_argument('--chunk-length', default=3, type=int)
  parser.add_argument('--enrollment-duration-threshold', default=2000, type=int)
  parser.add_argument('--combine', dest='combine', action='store_true')
  parser.add_argument('--no-combine', dest='combine', action='store_false')
  parser.add_argument('--num-jobs', default=mp.cpu_count(), type=int)

  parser.set_defaults(combine=True)

  cfg = parser.parse_args()


  print(f'Creating the output folder {cfg.output_folder}')
  if not os.path.exists(cfg.output_folder):
    os.makedirs(cfg.output_folder)

  print(f'Creating the logs folder {cfg.logs_folder}')
  if not os.path.exists(cfg.logs_folder):
    os.makedirs(cfg.logs_folder)

  # print('Saving the current configuration')
  # with open(os.path.join(cfg.logs_folder, 'config.txt'), 'w') as config_file:
  #   json.dump(cfg.__dict__, config_file)
  file_utils.save_config(cfg.logs_folder, cfg.__dict__)

  number_of_processors = mp.cpu_count()
  if cfg.num_jobs > number_of_processors:
    print(f'The number of jobs {cfg.num_jobs} is larger than the number of processors {number_of_processors}.')

  num_jobs = min(cfg.num_jobs, number_of_processors)
  print(f'Using {num_jobs} jobs')

  pool = mp.Pool(num_jobs)

  start_time = time.time()
  meeting_list_folders = os.listdir(cfg.audio_folder)
  # [TODO] is there a better way to view the progress?
  for meeting_id in tqdm(meeting_list_folders, total=len(meeting_list_folders)):
    pool.apply_async(
      process_meeting_folder,
      args=(cfg.logs_folder, meeting_id, cfg.audio_folder, cfg.output_folder,
            cfg.annotations_folder, cfg.offset, cfg.enrollment_duration_threshold,
            cfg.chunk_length, cfg.combine),
      callback=collect_extraction_result
    )

  pool.close()
  pool.join()

  end_time = time.time()
  print('The extraction has been finished.')
  print(f'Number of successfully processed meetings {number_of_processed_meetings} out of {len(meeting_list_folders)}.')
  print('Time spent: {:.2f} minutes'.format((end_time - start_time) / 60))

if __name__ == '__main__':
  main()