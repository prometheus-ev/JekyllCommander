function autocomplete_source(elem) {
  return $('#search form').attr('action') + '?type=' + $('#search_type').val();
}

$(document).ready(function() {
  if (!window.location.hash) {
    var i = $('#main input[type=text]').first()
    var v = i.val();
    if (v && v.trim().length === 0) {
      i.focus();
    }
  }

  $('#spinner')
    .ajaxStart(function() {
        $(this).show();
    })
    .ajaxStop(function() {
        $(this).hide();
    });

  $('#search_query').autocomplete({
    source: autocomplete_source(),
    focus:  function(event, ui) {
      return false;
    },
    select: function(event, ui) {
      window.location.href = $(ui.item).val();
      return false;
    }
  });

  $('#search_type').change(function() {
    $('#search_query').autocomplete(
      'option', 'source', autocomplete_source()
    );
  });
});
