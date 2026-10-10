// few suggested questions on the ask page
for(let b of document.querySelectorAll('[data-example]')) {
  b.addEventListener('click',()=>{
    document.getElementById('novaQuestion').value=b.dataset.example;
    document.getElementById('novaQuestion').focus();
  });
}
let about=new URLSearchParams(location.search).get('about');
if(about && about.length<90) {
  document.getElementById('novaQuestion').value='Tell me about '+about;
}
