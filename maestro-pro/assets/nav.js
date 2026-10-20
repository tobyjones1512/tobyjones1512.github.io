(function(){
var h=document.querySelector('header.top'),n=h&&h.querySelector('.top__links');
if(!n)return;
var b=document.createElement('button');
b.className='top__toggle';b.type='button';b.textContent='Menu';
b.setAttribute('aria-expanded','false');b.setAttribute('aria-controls','top-links');n.id='top-links';
b.onclick=function(){b.setAttribute('aria-expanded',h.classList.toggle('open'))};
h.insertBefore(b,n);
})();
