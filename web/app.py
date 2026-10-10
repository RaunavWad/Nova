from flask import Flask, render_template, request, jsonify
from datetime import datetime, timezone
from dotenv import load_dotenv
from sky_data import get_sky, object_info, fact_for
from functools import lru_cache
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
        print('sky error',repr(e))
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
            model='gpt-6-luna',
            reasoning={'effort':'none'},
            instructions=(
                'You explain astronomy to blind or visually impaired teenagers '
                'Write 2 short interesting sentences in natural everyday English '
                'Use only the supplied scientific facts, do not invent numbers, colors, history, '
                'mythology or claims about visibility '
                'Do not say you are an AI and do not use generic inspirational language '
                'Do not end the description with a period, no bullet points'
            ),
            input='Describe this real astronomical object using only these facts: '+facts,
            max_output_tokens=140
        )
        txt = reply.output_text.strip()
        if txt: return {'text':txt,'ai':True}
    except Exception as e:
        print('AI failed',repr(e))

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


if __name__ == '__main__':
    app.run(debug=True)
