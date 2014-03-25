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
    
    #����� �������� ����������
    $self->{_output}  = "/path/to/output.rss";
    
    #�������� RSS-������
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
        url         => "",          # * URL ����������� GIF, JPEG ��� PNG, ��������������� �����. 
        title       => "",          # - ��-��������� title ������
        link        => "",          # - ��-��������� link ������
        width       => "",          # -
        height      => "",          # -
        description => "",          # -
    };
    
    $self->{_skipDays} = [];        # - ���������� ����� ���� ������
    $self->{_skipHours} = [];       # - ����, 0-23
    
    # �������� ������ RSS-�����:  query ��� table
    $self->{_query} = "";
    $self->{_table} = "";
    $self->{_where} = "";
    $self->{_order} = "id desc";                       # �������� ��� table-�������
    $self->{_params} = [];
    
    $self->{_item_config} = {
        #������ ������������ title ��� description, ��� ��������� �� �����������
        title           => [{},{}],       #Required. Defines the title of the item
        description     => {},       #Required. Describes the item
        link            => "",       #Required. Defines the hyperlink to the item
        author          =>"",       # E-mail  Optional. Specifies the e-mail address to the author of the item
        comments        =>"",       # _������_    Optional. Allows an item to link to comments about that item
        enclosure       =>"",       # _������ �� ����_ ��������� - length,type,url
        #guid            =>"",      # + Attrib "isPermaLink"  Optional. Defines a unique identifier for the item.  
        pubDate         =>"",       # _����_ Optional. Defines the last-publication date for the item
        source          =>"",       # ������ �� ��������, �������� url Optional. Specifies a third-party source for the item
        
        category        =>"",       # _��������_   ��������� Optional. Defines one or more categories the item belongs to
    };
    
    #Item:
    
    #{FUNC  => "MethodName" }         # ������������� ��������� ������ �������
    #{RFUNC => "MethodName" }         # ��� ������, ������������� ����� XML (��������� � ����� ���� ��������!)
    #{TEXT  =>  "Static text"}        # ����������� �����
    #{FIELD => ""}                    # �������� ����
    #{PFIELD=> ""}                    # Page ?
    
    $self->{_filter} = [
        {FUNC =>"method"},                             # ����� �������� ������.. ����� �� ?
        {RFUNC =>"method"},                            # ����� �������� ����
        {FIELD=>"showonsite1", VALUE=>"1"},            # ��������
        {FIELD=>"showonsite2", VALUES=>[1,2,3]     },  # ���� �� ��������
        {WHERE=>"shos=? or shos2=?", PARAMS=>[1,2] },  # ����-��������� ����������
        {WHERE=>"showonsite1", PARAMS=>1           },  # ���� ��������
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
    <!-- ������������ �������� ������ -->
    <title>������� �������</title>
    <link>http://www.vesti70.ru/</link>
    <description>������� ������</description>

    <!-- �������������� �������� ������ -->
    <language>en-us</language>                                          <!-- ���� ������ (en-us - ����������; ru - �������). -->
    <copyright>2006 Refsnes Data as. All rights reserved.</copyright>   <!-- �������� �� ��������� �� RSS �����.-->
    <managingEditor>editor@w3schools.com</managingEditor>   <!-- Email ����� �������������� �� ������� ������.  -->
    <webMaster>webmaster@w3schools.com</webMaster>          <!-- Email ����� �������������� �� ����������� ����� ���������� ������. -->
    
    <pubDate>Thu, 27 Apr 2006</pubDate>                     <!-- ����-����� ��������� ����������     -->
    <lastBuildDate>Thu, 27 Apr 2006</lastBuildDate>         <!-- ����-����� ���������� ��������� rss -->
    
    <category>IT/Internet/Web development</category>        <!--  �� ����� ������� ... -->
    
    <generator>NG CMS ver 4.3</generator>
    
    <docs> URL </docs> <!-- �� ����� ;-) -->
    
    <cloud domain="www.w3schools.com" port="80" path="/RPC" registerProcedure="NotifyMe" protocol="xml-rpc" />
    
    <ttl>60</ttl> <!-- ����� �����; ���������� �����, �� ������� ����� ����� ������������ ����� ����������� � �������. -->
    
    <image>
        <url>http://vesti70.ru/img/rss/logo.gif</url> <!-- URL ����������� GIF, JPEG ��� PNG, ��������������� �����. -->
        <title>������� �������</title>                <!-- �������� ��� Alt ��������-->
        <link>http://www.vesti70.ru/</link>           <!-- URL �����; ����������� ������ ����� ������� ������� �� ���� ����. (��� �������, <title> � <link> ����������� ������ ��������� � <title> � <link> ������. -->
        
        <!-- �������������� �������� -->
        <width>         <!-- ������ � ������ ����������� � ��������.  ������������ ������ � 144, �� ��������� � 88 -->
        <height>        <!-- ������������ ������ � 400, �� ��������� � 31.-->
        <description>   <!-- �������� �����, ���������� � ������� title ������, �������������� ������ ����������� � HTML-�����������. -->
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
        <!-- ������ ������������ title ��� description, ��� ��������� �� �����������>
        <title>$stat->{name}</title>
        <link>http://vesti70.ru/stats/full/?id=$stat->{id}</link>
        <description>$stat->{short_text}</description>
        
        <-- ������ ���... 
        <category>News</category>   
        <category>Tutorial</category>  -->
        
        <!-- �������������� �������� -->
        <enclosure url="$stat->{small_image}" type="image/jpeg"/>
        
        <pubDate>$stat->{stats_date}</pubDate>
        
        
        <yandex:full-text>$stat->{full_text}</yandex:full-text>
    </item>
</channel>;
</rss>;

=cut

return 1;
END{};
 