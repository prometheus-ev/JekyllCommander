$(document).ready(function() {
  if (!window.location.hash) {
    var i = $('#main input[type=text]').first();
    if (i && i.val().trim().length === 0) {
      i.focus();
    }
  }
});
