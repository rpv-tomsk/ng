package NG::Module::RSSGenerator;
use strict;

#use NG::Event;
#use vars qw(@ISA);
#@ISA = qw(NG::Event);

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->init(@_);
    $self->config();
    return $self; 
};

sub init {
    my $self = shift;
    
    $self->{_channel} = {};
};

sub config {
    my $self = shift;
    
    #Место хранения результата
    $self->{_output}  = "/path/to/output.rss";
    
    #Свойства RSS-канала
    $self->{_channel} = {
        title       => "",         # *
        link        => "",         # *
        description => "",         # *
        language    => "",         # -
        copyright   => "",         # -
        managingEditor => "",      # -
        webMaster   => "",         # -
        generator   => "",         # -
        ttl         => 60,         # - 
    };
    
    $self->{_channel_image} = {
        url         => "",          # * URL изображения GIF, JPEG или PNG, представляющего канал. 
        title       => "",          # - по-умолчанию title канала
        link        => "",          # - по-умолчанию link канала
        width       => "",          # -
        height      => "",          # -
        description => "",          # -
    };
    
    $self->{_skipDays} = [];        # - Английские имена дней недели
    $self->{_skipHours} = [];       # - Часы, 0-23
    
    # Источник данных RSS-ленты:  query или table
    $self->{_query} = "";
    $self->{_table} = "";
    $self->{_where} = "";
    $self->{_order} = "id desc";                       # Параметр для table-запроса
    $self->{_params} = [];
    
    $self->{_item_config} = {
        #Должен существовать title или description, все параметры не обязательны
        title           => [{},{}],       #Required. Defines the title of the item
        description     => {},       #Required. Describes the item
        link            => "",       #Required. Defines the hyperlink to the item
        author          =>"",       # E-mail  Optional. Specifies the e-mail address to the author of the item
        comments        =>"",       # _ссылка_    Optional. Allows an item to link to comments about that item
        enclosure       =>"",       # _ссылка на файл_ Аттрибуты - length,type,url
        #guid            =>"",      # + Attrib "isPermaLink"  Optional. Defines a unique identifier for the item.  
        pubDate         =>"",       # _дата_ Optional. Defines the last-publication date for the item
        source          =>"",       # ссылка на источник, аттрибут url Optional. Specifies a third-party source for the item
        
        category        =>"",       # _перечень_   категорий Optional. Defines one or more categories the item belongs to
    };
    
    #Item:
    
    #{FUNC  => "MethodName" }         # Подставляется результат вызова функции
    #{RFUNC => "MethodName" }         # Имя метода, возвращающего кусок XML (параметры и вызов надо уточнить!)
    #{TEXT  =>  "Static text"}        # Статический текст
    #{FIELD => ""}                    # Значение поля
    #{PFIELD=> ""}                    # Page ?
    
    $self->{_filter} = [
        {FUNC =>"method"},                             # Метод проверки вообще.. Нужен ли ?
        {RFUNC =>"method"},                            # Метод проверки ряда
        {FIELD=>"showonsite1", VALUE=>"1"},            # Значение
        {FIELD=>"showonsite2", VALUES=>[1,2,3]     },  # Одно из значений
        {WHERE=>"shos=? or shos2=?", PARAMS=>[1,2] },  # Один-несколько параметров
        {WHERE=>"showonsite1", PARAMS=>1           },  # Один параметр
    ];
    
};

sub processEvent {
    my $self = shift;
    my $event = shift;
    
    print STDERR "FUCKYOU";
    return 0 unless ref $event eq "NG::Module::List::Event";
};

=head

http://www.w3schools.com/rss/rss_reference.asp

<?xml version=\"1.0\" encoding=\"windows-1251\"?>
<rss version=\"2.0\" xmlns=\"http://backend.userland.com/rss2\" xmlns:yandex=\"http://news.yandex.ru\">
<channel>
    <!-- Обязательные элементы канала -->
    <title>Томский вестник</title>
    <link>http://www.vesti70.ru/</link>
    <description>Новости Томска</description>

    <!-- Необязательные элементы канала -->
    <language>en-us</language>                                          <!-- Язык канала (en-us - Английский; ru - Русский). -->
    <copyright>2006 Refsnes Data as. All rights reserved.</copyright>   <!-- Сведения об авторстве на RSS канал.-->
    <managingEditor>editor@w3schools.com</managingEditor>   <!-- Email адрес ответственного за контент канала.  -->
    <webMaster>webmaster@w3schools.com</webMaster>          <!-- Email адрес ответственного за техническую часть публикации канала. -->
    
    <pubDate>Thu, 27 Apr 2006</pubDate>                     <!-- дата-время последней публикации     -->
    <lastBuildDate>Thu, 27 Apr 2006</lastBuildDate>         <!-- дата-время последнего изменения rss -->
    
    <category>IT/Internet/Web development</category>        <!--  На время отложим ... -->
    
    <generator>NG CMS ver 4.3</generator>
    
    <docs> URL </docs> <!-- Не нужен ;-) -->
    
    <cloud domain="www.w3schools.com" port="80" path="/RPC" registerProcedure="NotifyMe" protocol="xml-rpc" />
    
    <ttl>60</ttl> <!-- Время жизни; количество минут, на которые канал может кешироваться перед обновлением с ресурса. -->
    
    <image>
        <url>http://vesti70.ru/img/rss/logo.gif</url> <!-- URL изображения GIF, JPEG или PNG, представляющего канал. -->
        <title>Томский вестник</title>                <!-- Значение для Alt картинки-->
        <link>http://www.vesti70.ru/</link>           <!-- URL сайта; изображение канала будет служить ссылкой на этот сайт. (Как правило, <title> и <link> изображения должны совпадать с <title> и <link> канала. -->
        
        <!-- Необязательные элементы -->
        <width>         <!-- ширина и высота изображения в пикселях.  Максимальная ширина — 144, по умолчанию — 88 -->
        <height>        <!-- Максимальная высота — 400, по умолчанию — 31.-->
        <description>   <!-- содержит текст, включаемый в атрибут title ссылки, сформированной вокруг изображения в HTML-отображении. -->
    </image>
    
    <skipDays>
        <day>Saturday</day>
        <day>Sunday</day>
    </skipDays>
    
    <skipHours>
        <hour>0</hour>
        <hour>1</hour>
        <hour>2</hour>
        <hour>3</hour>
        <hour>4</hour>
        <hour>5</hour>
        <hour>6</hour>
        <hour>7</hour>
        <hour>17</hour>
        <hour>18</hour>
        <hour>19</hour>
        <hour>20</hour>
        <hour>21</hour>
        <hour>22</hour>
        <hour>23</hour>
    </skipHours>

    <item>
        <!-- Должен существовать title или description, все параметры не обязательны>
        <title>$stat->{name}</title>
        <link>http://vesti70.ru/stats/full/?id=$stat->{id}</link>
        <description>$stat->{short_text}</description>
        
        <-- сложно это... 
        <category>News</category>   
        <category>Tutorial</category>  -->
        
        <!-- необязательный параметр -->
        <enclosure url="$stat->{small_image}" type="image/jpeg"/>
        
        <pubDate>$stat->{stats_date}</pubDate>
        
        
        <yandex:full-text>$stat->{full_text}</yandex:full-text>
    </item>
</channel>;
</rss>;

=cut

return 1;
END{};
 