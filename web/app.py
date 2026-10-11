"""NOVA website and the routes used by the sky map."""

from datetime import datetime, timezone
from functools import lru_cache
from io import BytesIO
from pathlib import Path
import math
import os
import re

import requests
from dotenv import load_dotenv
from flask import Flask, jsonify, render_template, request, send_file

from sky_data import fact_for, get_sky, object_info

# Find .env in the web folder, even if Flask was started somewhere else.
load_dotenv(Path(__file__).with_name('.env'))

from voice_mode import real_astronomy_answer, router_chat, voice_routes

app = Flask(__name__)
app.register_blueprint(voice_routes)


# The four website pages
@app.get('/')
def home():
    return render_template('index.html')


@app.get('/explore')
def explore():
    return render_template('explore.html')


@app.get('/ask')
def ask_nova():
    return render_template('ask.html')


@app.get('/guide')
def guide():
    return render_template('guide.html')


@app.get('/api/sky')
def sky():
    """Calculate the sky for a location and a time."""
    try:
        lat = float(request.args.get('lat', 40.2146))
        lon = float(request.args.get('lon', -74.6193))
        at = request.args.get('at')

        if not (math.isfinite(lat) and math.isfinite(lon)):
            return jsonify(error='Location is invalid'), 400
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            return jsonify(error='Location is invalid'), 400

        # The browser sends ISO dates with a timezone.
        dt = datetime.fromisoformat(at.replace('Z', '+00:00')) if at else datetime.now(timezone.utc)
        if dt.tzinfo is None or not (1900 <= dt.year <= 2050):
            return jsonify(error='Use a valid date with a timezone from 1900 to 2050'), 400

        return jsonify(get_sky(lat, lon, dt))
    except (ValueError, OverflowError, TypeError):
        return jsonify(error='Invalid sky settings'), 400
    except Exception as error:
        print('Sky error:', type(error).__name__)
        return jsonify(error='Could not load the sky data, check the Flask terminal'), 500


def safe_description(text, item, facts):
    # Some free models return their notes about the prompt instead of a description.
    # We never want that showing up on the page or getting read by ElevenLabs.
    if not isinstance(text, str):
        return False

    text = text.strip()
    words = text.split()
    if not 6 <= len(words) <= 65 or len(text) > 500:
        return False
    if '\n' in text or '<' in text or '>' in text or '?' in text:
        return False

    # A real description should say which star or planet it is talking about.
    if item['name'].lower() not in text.lower():
        return False

    # Reject instructions, model notes, and anything that looks like AI reasoning.
    notes = (
        r'\b(?:the user|user wants|the prompt|provided facts|given facts|'
        r'instructions|system message|assistant response|final answer|'
        r'we need|i need|i should|let me think|wait:|thinking|'
        r'user safety|safety label|safety rating|safety verdict|content policy|plain text|'
        r'no final period|two sentences|2 sentences|do not|must not|'
        r'output should|the output|my response|the task|'
        r'here is the description|here\x27s the description)\b'
    )
    if re.search(notes, text, re.IGNORECASE):
        return False
    if re.match(r'^(?:analysis|reasoning|note|step \d+)\s*:', text, re.IGNORECASE):
        return False

    # Don't accept new numbers that weren't in our astronomy data.
    # It catches made-up distances, temperatures, and magnitudes.
    numbers_in_facts = set(re.findall(r'\d+(?:\.\d+)?', facts))
    numbers_in_answer = set(re.findall(r'\d+(?:\.\d+)?', text))
    if not numbers_in_answer.issubset(numbers_in_facts):
        return False

    return True


@lru_cache(maxsize=400)
def describe_object(object_id):
    """Use OpenRouter for a short description, or use our catalog facts."""
    item = object_info(object_id)
    if not item:
        return None

    facts = fact_for(item)
    key = os.getenv('OPENROUTER_API_KEY', '').strip()

    # The descriptions still work without any AI account.
    if not key:
        return {'text': facts, 'ai': False}

    try:
        messages = [
            {
                'role': 'system',
                'content': (
                    'You describe real astronomical objects for blind and visually impaired teenagers. '
                    'Use ONLY the provided facts and write 2 short, clear sentences. '
                    'Do not make up facts, numbers, history, mythology, or visibility information. '
                    'Use plain text with no lists and no final period. '
                    'Do not give safety labels or talk about the instructions.'
                )
            },
            {
                'role': 'user',
                'content': 'Describe this astronomy object using these facts only: ' + facts
            }
        ]
        model = os.getenv('OPENROUTER_MODEL', '').strip() or 'openrouter/free'
        text = router_chat(messages, 170, model, 0.2).strip()

        # Only use an AI description if it actually describes this object.
        # Otherwise the catalog facts are safer and still work with narration.
        if real_astronomy_answer(text) and safe_description(text, item, facts):
            return {'text': text.strip().rstrip('.'), 'ai': True}
    except (requests.RequestException, RuntimeError, ValueError) as error:
        print('OpenRouter description problem:', type(error).__name__)

    return {'text': facts, 'ai': False}


@app.post('/api/describe')
def describe():
    data = request.get_json(silent=True) or {}
    object_id = data.get('id', '') if isinstance(data, dict) else ''
    if not isinstance(object_id, str) or len(object_id) > 60:
        return jsonify(error='Invalid object'), 400

    description = describe_object(object_id)
    if description is None:
        return jsonify(error='Object not found'), 404
    return jsonify(description)


@app.get('/api/services')
def services():
    # This only checks that the keys exist, not that the account has credits.
    return jsonify(
        elevenlabs=bool(os.getenv('ELEVENLABS_API_KEY') and os.getenv('ELEVENLABS_VOICE_ID')),
        openrouter=bool(os.getenv('OPENROUTER_API_KEY'))
    )


@lru_cache(maxsize=80)
def voice_audio(object_id):
    """Make a voice clip once and reuse it when the same object is selected."""
    key = os.getenv('ELEVENLABS_API_KEY')
    voice_id = os.getenv('ELEVENLABS_VOICE_ID', '').strip()
    if not key or not voice_id:
        return None
    if not re.fullmatch(r'[A-Za-z0-9_-]{6,80}', voice_id):
        raise ValueError('Voice ID is invalid')

    description = describe_object(object_id)
    if not description or not description['text'].strip():
        return None

    response = requests.post(
        'https://api.elevenlabs.io/v1/text-to-speech/' + voice_id,
        params={'output_format': 'mp3_44100_128'},
        headers={'xi-api-key': key, 'Content-Type': 'application/json'},
        json={'text': description['text'].strip()[:1500], 'model_id': 'eleven_multilingual_v2'},
        timeout=(6, 35)
    )
    response.raise_for_status()
    return response.content


@app.post('/api/speak')
def speak():
    # Only catalog objects can be read here, not random text from a browser.
    data = request.get_json(silent=True) or {}
    object_id = data.get('id', '') if isinstance(data, dict) else ''
    if not isinstance(object_id, str) or len(object_id) > 60:
        return jsonify(error='Invalid object'), 400
    if not os.getenv('ELEVENLABS_API_KEY') or not os.getenv('ELEVENLABS_VOICE_ID'):
        return jsonify(error='ElevenLabs is not set up'), 503

    try:
        audio = voice_audio(object_id)
        if not audio:
            return jsonify(error='Object not found'), 404
        return send_file(BytesIO(audio), mimetype='audio/mpeg', download_name='nova.mp3')
    except requests.exceptions.HTTPError as error:
        # Don't put private provider details in the response.
        status = error.response.status_code if error.response is not None else ''
        print('ElevenLabs HTTP error:', status)
        return jsonify(error='ElevenLabs rejected the request, check your key, voice ID and credits'), 502
    except requests.exceptions.RequestException:
        print('ElevenLabs network error')
        return jsonify(error='ElevenLabs could not be reached'), 502
    except Exception as error:
        print('Voice error:', type(error).__name__)
        return jsonify(error='Could not create the narration'), 502


if __name__ == '__main__':
    app.run(debug=True)
