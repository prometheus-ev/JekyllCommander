document.observe('dom:loaded', function() {
  if (!window.location.hash) {
    var i = $('main').select('input[type=text]')[0];
    if (i && i.value.blank()) {
      i.focus();
    }
  }
}.bindAsEventListener(document));
