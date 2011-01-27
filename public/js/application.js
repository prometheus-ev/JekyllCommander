function autocomplete_source(elem) {
  return $('#search form').attr('action') + '?type=' + $('#search_type').val();
}

function add_header_field() {
  var count = $('#main form').data('add_header_filed_count');
  if (count) {
    ++count;
  } else {
    count = 1;
  }
  $('#main form').data('add_header_filed_count', count);

  var content = '<p><label for="header_key_count">Name:</label><label for="header_val_count"'
    + ' style="padding-left: 120px;">Wert:</label><br />'
    + '<input type="text" name="add_header_key_count" size="15" id="header_key_count" /> : '
    + '<input type="text" name="add_header_val_count" size="35" id="header_val_count" /></p>';
  content = content.replace(/count/g, count);

  $('#add-header-field').before(content);
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
