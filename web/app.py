from flask import Flask, render_template, request, jsonify, send_file
from datetime import datetime, timezone
from dotenv import load_dotenv
from sky_data import get_sky, object_info, fact_for
from functools import lru_cache
from io import BytesIO
import requests
import re
import os

load_dotenv()
app = Flask(__name__)

@app.route('/')
def home():
    return render_template('index.html')


@app.get('/api/sky')
def sky():
    try:
        lat = float(request.args.get('lat',40.2146))
        lon = float(request.args.get('lon',-74.6193))
        at = request.args.get('at')
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            return jsonify(error='Location is invalid'),400
        dt = datetime.fromisoformat(at.replace('Z','+00:00')) if at else datetime.now(timezone.utc)
        if not dt.tzinfo or not (1900 <= dt.year <= 2050):
            return jsonify(error='Use a valid date with a timezone from 1900 to 2050'),400
        return jsonify(get_sky(lat,lon,dt))
    except ValueError as e:
        return jsonify(error='Invalid sky settings'),400
    except Exception as e:
        print('sky error',type(e).__name__)
        return jsonify(error='Could not load the sky data, check the Flask terminal'),500


@lru_cache(maxsize=400)
def ai_text(id):
    item = object_info(id)
    if not item: return None
    facts = fact_for(item)
    key = os.environ.get('OPENAI_API_KEY')
    if not key: return {'text':facts,'ai':False}

    try:
        from openai import OpenAI
        client = OpenAI(api_key=key)
        reply = client.responses.create(
            model=os.environ.get('OPENAI_MODEL', 'gpt-4.1-mini'),
            instructions=(
                'You explain astronomy to blind or visually impaired teenagers '
                'Write 2 short interesting sentences in natural everyday English '
                'Use only the supplied scientific facts, do not invent numbers, colors, history, '
                'mythology or claims about visibility '
                'Do not say you are an AI and avoid generic inspirational language '
                'Write plain text, no bullet points, do not end the description with a period'
            ),
            input='Describe this real astronomical object using only these facts: '+facts,
            max_output_tokens=170
        )
        txt = reply.output_text.strip()
        if txt: return {'text':txt,'ai':True}
    except Exception as e:
        print('AI description failed:',type(e).__name__)

    return {'text':facts,'ai':False}


@app.post('/api/describe')
def describe():
    data = request.get_json(silent=True) or {}
    id = data.get('id','')
    if not isinstance(id,str) or len(id)>60:
        return jsonify(error='Invalid object'),400
    answer = ai_text(id)
    if not answer: return jsonify(error='Object not found'),404
    return jsonify(answer)


# just checks whether keys are in .env, doesn't test credits
@app.get('/api/services')
def services():
    return jsonify(
        elevenlabs=bool(os.getenv('ELEVENLABS_API_KEY') and os.getenv('ELEVENLABS_VOICE_ID')),
        openai=bool(os.getenv('OPENAI_API_KEY'))
    )


# cache clips so repeat clicks don't use more voice credits
@lru_cache(maxsize=80)
def voice_audio(id):
    key = os.getenv('ELEVENLABS_API_KEY')
    voice = os.getenv('ELEVENLABS_VOICE_ID','').strip()
    if not key or not voice: return None
    if not re.fullmatch(r'[A-Za-z0-9_-]{6,80}',voice):
        raise ValueError('Voice ID is invalid')

    story = ai_text(id)
    if not story: return None
    narration = story['text'].strip()
    if not narration: return None

    r = requests.post(
        'https://api.elevenlabs.io/v1/text-to-speech/' + voice,
        params={'output_format':'mp3_44100_128'},
        headers={'xi-api-key':key,'Content-Type':'application/json'},
        json={'text':narration[:1500],'model_id':'eleven_multilingual_v2'},
        timeout=(6,35)
    )
    r.raise_for_status()
    return r.content


# no arbitrary text allowed, only a known star or planet ID
@app.post('/api/speak')
def speak():
    data = request.get_json(silent=True) or {}
    id = data.get('id','')
    if not isinstance(id,str) or len(id)>60:
        return jsonify(error='Invalid object'),400
    if not os.getenv('ELEVENLABS_API_KEY') or not os.getenv('ELEVENLABS_VOICE_ID'):
        return jsonify(error='ElevenLabs is not set up'),503

    try:
        mp3 = voice_audio(id)
        if not mp3: return jsonify(error='Object not found'),404
        return send_file(BytesIO(mp3),mimetype='audio/mpeg',download_name='nova.mp3')
    except requests.exceptions.HTTPError as e:
        # do not expose keys or provider error details to the browser
        print('ElevenLabs HTTP error', e.response.status_code if e.response is not None else '')
        return jsonify(error='ElevenLabs rejected the voice request, check your key, voice ID and credits'),502
    except requests.exceptions.RequestException:
        print('ElevenLabs network error')
        return jsonify(error='ElevenLabs could not be reached'),502
    except Exception as e:
        print('voice error',type(e).__name__)
        return jsonify(error='Could not create the narration'),502


if __name__ == '__main__':
    app.run(debug=True)
