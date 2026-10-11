// the ask nova voice thing
// kept separate from the sky map so we don't mess up the old buttons

(() => {
  const find = id => document.getElementById(id);
  const mic = find('novaMic'), finish = find('novaFinish');
  const cancel = find('novaCancel'), stopBtn = find('novaStop');
  const form = find('novaQuestionForm'), question = find('novaQuestion');
  const status = find('novaVoiceStatus'), reply = find('novaVoiceReply');
  const answerText = find('novaAnswer'), replay = find('novaReplay');

  if(!mic || !form) return;

  let recorder = null, micStream = null, chunks = [];
  let recTimer = null, skipRecording = false;
  let requestController = null, audioPlayer = null, audioUrl = null;
  let lastAnswer = '', speechToken = '', conversationToken = '', turn = 0;

  const sound = window.novaAudio;
  const sayStatus = t => status.textContent = t;

  function stopAnswer() {
    turn++;
    if(requestController) requestController.abort();
    requestController = null;
    if(audioPlayer) {audioPlayer.pause();audioPlayer=null}
    if(audioUrl) {URL.revokeObjectURL(audioUrl);audioUrl=null}
    if('speechSynthesis' in window) speechSynthesis.cancel();
    sound.duck(false);
  }

  function stopMicTracks() {
    if(micStream) micStream.getTracks().forEach(track=>track.stop());
    micStream=null;
    if(recTimer) clearTimeout(recTimer);
    recTimer=null;
    sound.duck(false);
  }

  function buttonsForRecording(on) {
    mic.disabled=on;
    mic.setAttribute('aria-pressed',String(on));
    finish.disabled=!on;
    cancel.disabled=!on;
  }

  function getContext() {
    return {
      selected:find('starName')?.textContent || '',
      direction:find('starDirection')?.textContent || '',
      place:find('place')?.selectedOptions?.[0]?.textContent || '',
      time:find('skyDate')?.value || ''
    };
  }

  async function postJSON(url, data, signal) {
    let res = await fetch(url, {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify(data), signal
    });
    let body = await res.json().catch(()=>({}));
    if(!res.ok) throw Error(body.error || 'Request failed');
    return body;
  }

  // browser speech only if elevenlabs voice fails
  function backupVoice(t) {
    if(!sound.canSpeak()) return;
    if(!('speechSynthesis' in window)) {
      sayStatus('Answer ready as text but audio is unavailable');
      return;
    }
    speechSynthesis.cancel();
    let s = new SpeechSynthesisUtterance(t);
    s.rate=.93;
    s.onend = () => sound.duck(false);
    s.onerror = () => sound.duck(false);
    sound.duck(true);
    speechSynthesis.speak(s);
  }

  async function playAnswer(text, token, mine) {
    // do not change the run number here or we'll cancel our own request
    if(mine!==turn) return;
    if(!sound.canSpeak()) {
      sayStatus('Answer ready as text  Turn on audio above to hear it');
      return;
    }

    requestController = new AbortController();
    sayStatus('Making the ElevenLabs voice');
    try {
      let res=await fetch('/api/voice/speak', {
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body:JSON.stringify({speech_token:token}),
        signal:requestController.signal
      });
      if(!res.ok) {
        let error = await res.json().catch(()=>({}));
        throw Error(error.error || 'Voice was unavailable');
      }
      let blob = await res.blob();
      if(mine!==turn || !sound.canSpeak()) return;

      audioUrl=URL.createObjectURL(blob);
      let url=audioUrl;
      audioPlayer=new Audio(url);
      sound.duck(true);
      audioPlayer.onended=()=>{
        sound.duck(false);
        if(audioPlayer)audioPlayer=null;
        URL.revokeObjectURL(url);
        if(audioUrl===url)audioUrl=null;
        if(mine===turn)sayStatus('Ready for your next question');
      };
      await audioPlayer.play();
      if(mine===turn) sayStatus('NOVA is speaking');
    } catch(e) {
      if(mine!==turn || e.name==='AbortError') return;
      sound.duck(false);
      console.log('NOVA audio fallback',e.message);
      sayStatus('ElevenLabs voice unavailable, using browser speech');
      backupVoice(text);
    } finally {
      if(mine===turn)requestController=null;
    }
  }

  // typed and spoken questions both end up going through here
  async function askQuestion(text) {
    text = text.trim();
    if(!text) { sayStatus('Type or say a question first'); return }
    if(text.length>650) {sayStatus('Question is too long');return}
    if(recorder && recorder.state==='recording') {
      sayStatus('Stop the recording before asking'); return;
    }

    stopAnswer();
    // stop any existing star narration too
    find('stopBtn')?.click();
    let mine=turn;
    question.value=text;
    reply.hidden=true;
    lastAnswer='';
    speechToken='';
    sayStatus('Checking your astronomy question');

    requestController=new AbortController();
    try {
      let d=await postJSON('/api/voice/ask', {
        question:text,
        conversation_token:conversationToken,
        context:getContext()
      },requestController.signal);
      if(mine!==turn) return;
      lastAnswer=d.answer;
      speechToken=d.speech_token || '';
      conversationToken=d.conversation_token || conversationToken;
      answerText.textContent=lastAnswer;
      reply.hidden=false;
      if(d.blocked) sayStatus('NOVA only answers astronomy questions');
      await playAnswer(lastAnswer,speechToken,mine);
    } catch(e) {
      if(mine!==turn || e.name==='AbortError') return;
      sayStatus(e.message);
    } finally {
      if(mine===turn)requestController=null;
    }
  }

  async function transcribe(blob) {
    stopAnswer();
    let mine=turn;
    sayStatus('Converting your voice to text');

    requestController=new AbortController();
    let fd=new FormData();
    let name=(blob.type || '').includes('mp4') ? 'question.m4a'
      : (blob.type || '').includes('ogg') ? 'question.ogg' : 'question.webm';
    fd.append('audio',blob,name);

    try {
      let res=await fetch('/api/voice/transcribe', {
        method:'POST',body:fd,signal:requestController.signal
      });
      let d=await res.json().catch(()=>({}));
      if(!res.ok)throw Error(d.error || 'Could not understand the recording');
      if(mine!==turn)return;
      question.value=d.text;
      // automatically ask OpenRouter what ElevenLabs heard
      askQuestion(d.text);
    } catch(e) {
      if(mine!==turn || e.name==='AbortError')return;
      sayStatus(e.message);
    } finally {
      if(mine===turn)requestController=null;
    }
  }

  // only turn the mic on after someone presses Start speaking
  async function startRecording() {
    if(!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) {
      sayStatus('This browser cannot record audio, type your question instead');
      return;
    }

    stopAnswer();
    find('stopBtn')?.click();
    let mine=turn;
    skipRecording=false;
    chunks=[];
    sayStatus('Waiting for microphone permission');
    mic.disabled=true;

    try {
      let stream=await navigator.mediaDevices.getUserMedia({audio:true});
      if(mine!==turn) {
        stream.getTracks().forEach(t=>t.stop());return;
      }
      micStream=stream;
      sound.duck(true); // less music getting into the microphone

      let types=['audio/webm;codecs=opus','audio/webm','audio/mp4','audio/ogg;codecs=opus'];
      let supported=types.find(type=>MediaRecorder.isTypeSupported(type));
      recorder=new MediaRecorder(stream,supported?{mimeType:supported}:undefined);

      recorder.ondataavailable=e=>{if(e.data.size>0)chunks.push(e.data)};
      recorder.onstop=()=>{
        stopMicTracks();
        buttonsForRecording(false);
        let result=new Blob(chunks,{type:recorder.mimeType || 'audio/webm'});
        chunks=[];
        if(skipRecording) {
          sayStatus('Recording canceled');return;
        }
        if(result.size<100) {
          sayStatus('No audio captured, try again');return;
        }
        transcribe(result);
      };

      recorder.start(250);
      buttonsForRecording(true);
      sayStatus('Listening now  Say your astronomy question');
      // auto stop so an accidental open microphone won't run forever
      recTimer=setTimeout(()=>finishRecording(),25000);
    } catch(e) {
      stopMicTracks();
      buttonsForRecording(false);
      sayStatus('Microphone unavailable  Check permissions or type the question');
    }
  }

  function finishRecording() {
    if(recorder && recorder.state==='recording') {
      sayStatus('Finishing your recording');
      recorder.stop();
    }
  }

  function cancelRecording() {
    skipRecording=true;
    stopAnswer();
    if(recorder && recorder.state==='recording') recorder.stop();
    else stopMicTracks();
    buttonsForRecording(false);
    sayStatus('Recording canceled');
  }

  mic.addEventListener('click',startRecording);
  finish.addEventListener('click',finishRecording);
  cancel.addEventListener('click',cancelRecording);
  stopBtn.addEventListener('click',()=>{
    stopAnswer();
    sayStatus('Response stopped');
  });
  replay.addEventListener('click',()=>{
    if(!lastAnswer)return;
    stopAnswer();
    find('stopBtn')?.click();
    playAnswer(lastAnswer,speechToken,turn);
  });

  // mute immediately stops responses even if we're still waiting for ElevenLabs
  document.addEventListener('nova:modechange', e => {
    if(e.detail.mode === 'off') {
      stopAnswer();
      sayStatus('Audio is off  You can still read the answer');
    }
  });

  form.addEventListener('submit',e=>{
    e.preventDefault();
    askQuestion(question.value);
  });
})();
