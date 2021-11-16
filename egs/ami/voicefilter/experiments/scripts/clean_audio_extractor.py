import argparse
import glob
import os

import xml.etree.ElementTree as ET

from pydub import AudioSegment


SEGMENT_TAG_NAME = 'segment'
TRANSCRIBER_START_TAG_NAME = 'transcriber_start'
TRANSCRIBER_END_TAG_NAME = 'transcriber_end'

DEFAULT_COMBINED_WAV_NAME = 'combined'


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


def get_output_files_folder(output_folder: str, meeting_id: str, speaker_id: int):
  """
  """
  return os.path.join(output_folder, 'segments', meeting_id, str(speaker_id))

def concatenate_audio_files(output_folder: str, meeting_id: str, speaker_id: int):
  """
  """
  output_files_folder = get_output_files_folder(output_folder, meeting_id, speaker_id)
  combined_file_path = os.path.join(output_files_folder, f'{DEFAULT_COMBINED_WAV_NAME}.wav')
  if os.path.exists(combined_file_path):
    os.remove(combined_file_path)

  speaker_segment_audio_files = glob.glob(
    f'{output_files_folder}/*.wav'
  )
  print(f'{len(speaker_segment_audio_files)} audio files found for speaker {speaker_id}, meeting {meeting_id}.')

  # [TODO] sort the segments first?
  speaker_wavs = [AudioSegment.from_wav(wav_path) for wav_path in speaker_segment_audio_files]
  speaker_combined_wav = speaker_wavs[0]

  for speaker_wav in speaker_wavs[1:]:
    speaker_combined_wav = speaker_combined_wav.append(speaker_wav)

  speaker_combined_wav.export(combined_file_path, format='wav')


def extract_clean_audio(meeting_id: str, audio_folder: str,
                        transcript_folder: str, output_folder: str,
                        offset: int, combine: bool):
  """
  Gets a file path where the recordings from individual headsets are located.
  Returns audio segments of individual speakers without overlapping with other speakers.
  """
  assert meeting_id, 'Meeting id needs to be specified'
  assert audio_folder, 'The folder where audio recordings are located needs to be specified'
  assert transcript_folder, 'The folder where transcript segments are located needs to be specified'

  print(f'Starting clean audio extraction: \
    meeting id = {meeting_id}, audio folder = {audio_folder}, transcript folder = {transcript_folder}...')

  if audio_folder.endswith('/'):
    audio_folder = audio_folder[:-1]

  if transcript_folder.endswith('/'):
    transcript_folder = transcript_folder[:-1]

  transcript_segment_files = glob.glob(f'{transcript_folder}/{meeting_id}.*.segments.xml')
  number_of_speakers = len(transcript_segment_files)

  print(f'Found {number_of_speakers} speakers in the transcript segments')

  print('Gathering segments...')
  segment_points = []
  for speaker_id_int in range(number_of_speakers):
    speaker_id_str = convert_speaker_id_int_to_str(speaker_id_int)
    transcript_file_path = os.path.join(transcript_folder, f'{meeting_id}.{speaker_id_str}.segments.xml')
    xml_tree = ET.parse(transcript_file_path)
    xml_root = xml_tree.getroot()

    for segment_xml in xml_root:
      if segment_xml.tag != SEGMENT_TAG_NAME:
        # Just ignore.
        continue
      if TRANSCRIBER_START_TAG_NAME not in segment_xml.attrib or TRANSCRIBER_END_TAG_NAME not in segment_xml.attrib:
        # Just ignore.
        print(f'Warning: found <segment> element without "transcriber_start" or "transcriber_end" attributes')
        continue
      
      # Time is stored in seconds. We convert it to milliseconds.
      start = int(float(segment_xml.attrib[TRANSCRIBER_START_TAG_NAME]) * 1000)
      end = int(float(segment_xml.attrib[TRANSCRIBER_END_TAG_NAME]) * 1000)

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
  for segment in segments_without_overlapping:
    speaker_id_int = convert_speaker_id_str_to_int(segment[0])
    segments_per_speaker[speaker_id_int] += 1
    start = segment[1]
    end = segment[2]
    audio_file_path = os.path.join(audio_folder, f'{meeting_id}.Headset-{speaker_id_int}.wav')   # e.g. ES2002a.Headset-1.wav
   
    whole_audio = AudioSegment.from_wav(audio_file_path) 
    audio_segment = whole_audio[start:end]

    output_files_folder = get_output_files_folder(
      output_folder,
      meeting_id,
      speaker_id_int
    ) #os.path.join(output_folder, 'segments', meeting_id, str(speaker_id_int))
    if not os.path.exists(output_files_folder):
      os.makedirs(output_files_folder)

    audio_segment.export(os.path.join(output_files_folder, f'{start}-{end}.wav'), format='wav')

  print(f'Clean audio segments have been successfully extracted. Segments per speaker: {segments_per_speaker}')

  if combine:
    print('Concatenating segments into one audio file.')
    for speaker_id_int in range(number_of_speakers):
      concatenate_audio_files(
        output_folder,
        meeting_id,
        speaker_id_int
      )

    print('Concatenation has been successfully performed.')


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument('--audio-folder', default='./../amicorpus', type=str)
  parser.add_argument('--segments-transcript-folder', default='./../annotations/segments', type=str)
  parser.add_argument('--output-folder', default='./../data/clean', type=str)
  parser.add_argument('--offset', default=200, type=int)
  parser.add_argument('--combine', dest='combine', action='store_true')
  parser.add_argument('--no-combine', dest='combine', action='store_false')

  parser.set_defaults(combine=True)

  cfg = parser.parse_args()

  for obj in os.listdir(cfg.audio_folder):
    if os.path.isdir(os.path.join(cfg.audio_folder, obj)):
      meeting_id = obj

      extract_clean_audio(
        #'./../amicorpus/ES2002a/audio/ES2002a.Headset-1.wav',
        #'./../annotations/segments/ES2002a.B.segments.xml'
        meeting_id,
        os.path.join(cfg.audio_folder, meeting_id, 'audio'),
        cfg.segments_transcript_folder,
        cfg.output_folder,
        cfg.offset,
        cfg.combine
      )

      # concatenate_audio_files(
      #   cfg.output_folder,
      #   meeting_id,
      #   0
      # )

if __name__ == '__main__':
    main()