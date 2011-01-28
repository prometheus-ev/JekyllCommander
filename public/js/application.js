function autocomplete_source(elem) {
  return $('#search form').attr('action') + '?type=' + $('#search_type').val();
}

function add_header_field() {
  var name = prompt('Name:');

  if (!name || name.trim().length < 1) {
    return;
  }

  var key = name.trim().replace(/\s+/, '_').toLowerCase();
  var id  = '_header_' + key;

  $('#header_fields').append('<p>' +
    '<label for="' + id + '">' + name + '</label>:<br />' +
    '<input type="text" id="' + id + '" name="header[' + key + ']" size="50" />' +
  '</p>');
}

$(document).ready(function() {
  var i = $('#main input[type=text]').first();
  if (i) {
    var v = i.val();
    if (v.trim().length < 1) {
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

  $('<input type="button" value="Add header field" />')
    .insertAfter('#header_fields')
    .click(add_header_field);
});
