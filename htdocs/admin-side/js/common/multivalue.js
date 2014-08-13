$.fn.multivalueWithAddToBase = function(options) {
    var items = this.find(".items"); //��������� �������
    var values = [];                 //ID ��������� ������� ����� �������
    
    var addToBase = this.find(".addToBase");  //������ ���������� ����� ������
    var addToBaseError = this.find(".addToBaseError");  // Span ������ ������ ���������� ������
    var autocompleteinput = this.find(".autocomplete"); // ���� ������/�����
    var multiValueValue   = this.find(".multiValueValue"); //���� ��������
    
    var options = $.extend({
        sortable: false,
        addition: false
    }, options );
    
    autocompleteinput.autocomplete({
        minLength: 3,
        source: function(request, response){
            addToBaseError.css('display', 'none');
            //����������� autocomplete � ������ ��� ��������� ���������
            var url = autocompleteinput.attr('data-searchUrl') + "&values=" + values;
            $.getJSON(url, request, function(data) {
                if (data.length ==0) {
                    addToBaseError.html('�������� � ����������� �� �������');
                    addToBaseError.css('display', 'inline');
                    addToBaseError.css('color', 'green');
                };
                response(data);
            });
        },
        select: function(event,item){
          addItemToList(item.item);
          this.value = "";
          return false;
        }
    });
    
    function doAddToBase () {
        var value = autocompleteinput.val();
        
        if (!value) return false;
        
        var data = {};
        data.value = value;
        
        addToBaseError.css('display', 'none');
        
        $.ajax({
            url: addToBase.attr('data-addUrl'),
            cache: false,
            type: 'POST',
            dataType: 'json',
            data: data,
            success: function(response) {
                if (response.error) {
                    addToBaseError.html(response.error);
                    addToBaseError.css('display', 'inline');
                    addToBaseError.css('color', 'red');
                }
                else if (response.id) {
                    addItemToList(response);
                    autocompleteinput.val("");
                }
                else {
                    addToBaseError.html('������ - ���������������� JSON-�����.');
                    addToBaseError.css('display', 'inline');
                    addToBaseError.css('color', 'red');
                };
            },
            error: function (xhr) {
                if (addToBaseError) {
                    addToBaseError.html('������ �������� �������, ��� ������: '+xhr.status);
                    addToBaseError.css('display', 'inline');
                    addToBaseError.css('color', 'red');
                };
            }
        });
        return false;
    };
    
    function updateValuesFromItems() {
        values = [];
        items.find("li").each(function(i, listItem) {
            values.push($(listItem).attr('data-id'));
        });
        values.join(',');
        if (multiValueValue)
            multiValueValue.val(values);
    };
    
    function deleteItem() {
        $(this).parent('li').remove();
        updateValuesFromItems();
        return false;
    };
    
    function addItemToList(item) {
        //��������, ��� �� ������ � ������.
        for (var key in values) {
            if (values[key] == item.id)
                return;
        };
        
        var item = items.append('<li class="ui-state-default" data-id="'+item.id+'"><span class="ui-icon ui-icon-arrowthick-2-n-s"></span>'+item.label+' <a href="#" class="deleteItem">[X]</a></li>');
        item.find(".deleteItem").click(deleteItem);
        updateValuesFromItems();
    };
    
    if (options.sortable) {
        items.sortable({
            update: function( event, ui ) {
                updateValuesFromItems();
            }
        });
        items.disableSelection();
    };
    if (options.addition)
        addToBase.click(doAddToBase);
    
    items.find(".deleteItem").click(deleteItem);
    
    if (multiValueValue) {
        var oldValue = multiValueValue.val();
        updateValuesFromItems();
        if (oldValue != values)
            alert('������������������ ID �� ���������! '+oldValue+' vs '+ values);
    }
    else {
        updateValuesFromItems();
    };
    
};
