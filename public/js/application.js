$(document).ready(function() {
  if (!window.location.hash) {
    var i = $('#main input[type=text]').first()
    var v = i.val();
    if (v && v.trim().length === 0) {
      i.focus();
    }
  }

  $('#search_query').autocomplete({
    source: $('#search form').attr('action'),
    search: function(event, ui) {
      return $('#search_type').val() === 'name';
    },
    focus:  function(event, ui) {
      return false;
    },
    select: function(event, ui) {
      window.location.href = $(ui.item).val();
      return false;
    }
  });
});
