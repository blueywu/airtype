const languageButtons = document.querySelectorAll('[data-set-language]');
const translatedElements = document.querySelectorAll('[data-zh][data-en]');
let language = localStorage.getItem('vremoter-language') ||
  (navigator.language.toLowerCase().startsWith('zh') ? 'zh' : 'en');

function applyLanguage(nextLanguage) {
  language = nextLanguage;
  document.documentElement.lang = language === 'zh' ? 'zh-Hans' : 'en';
  translatedElements.forEach((element) => {
    element.textContent = element.dataset[language];
  });
  languageButtons.forEach((button) => {
    button.classList.toggle('active', button.dataset.setLanguage === language);
  });
  const audioImage = document.querySelector('[data-localized-audio]');
  if (audioImage) {
    audioImage.src = language === 'zh'
      ? 'assets/screenshots/vremoter-audio-1.1.1.png'
      : 'assets/screenshots/vremoter-audio-1.1.1-en.png';
  }
  const mappingImage = document.querySelector('[data-localized-mapping]');
  if (mappingImage) {
    mappingImage.src = language === 'zh'
      ? 'assets/screenshots/vremoter-mapping-chromecast-1.1.1.png'
      : 'assets/screenshots/vremoter-mapping-chromecast-1.1.1-en.png';
  }
  localStorage.setItem('vremoter-language', language);
}

languageButtons.forEach((button) => {
  button.addEventListener('click', () => applyLanguage(button.dataset.setLanguage));
});

applyLanguage(language);
