#!/usr/bin/env ruby
#####################################################################
#AiM: ACK Nagios Notification by Forwarding Notification Mail to
#	Nagios' PrivateGMail A/C with Custom Tweaked Subject
#
#this script access GMail over IMAP and fetches InBox Mails
#then it checks for Sender of Mail
#if Sender=NagiosContact then send Mail Subject to Perl script to ACK
#moves fetched Mail to Archive with a Label, deletes from InBox
#####################################################################
##############################START-SCRIPT##############################
require 'net/imap'

nagID = 'myNagiosBox1'

CONFIG = {
  :host     => 'imap.gmail.com',
  :username => 'urNagiosMailID@gmail.com', #its fake, change it
  :password => 'urNagiosPassword', #its fake, change it
  :port     => 993,
  :ssl      => true
}

#####################################################################
###############################ACK-METHOD##############################
def nagiosACK(eMailSubject,machineString)
    machineID = machineString
    subject = eMailSubject
    printMsg="echo 'Subject: " + subject + "' >> /var/log/nagAck.log"
    system(printMsg)
    @commandFile = '/usr/local/nagios/var/rw/nagios.cmd'
    @subjectTokens =subject.split(/\s/)

    if @subjectTokens[0]!=machineID
      system('echo "@Error: eMail Subject has Wrong Machine ID" >> /var/log/nagAck.log')
      return false
    end

    #composing acknowledgement string for nagios.cmd
    if subject.index("Host") != nil 
      #in above kind of SUBJECT Line, default HOST info is 8th Word, so
      hostNfo = @subjectTokens[7]
      #preparing host acknowledgement string
      @ackCmd="ACKNOWLEDGE_HOST_PROBLEM;"+hostNfo
      @ackCmd=@ackCmd+";1;1;1;urNagiosMailID@gmail.com;acknowledged through nagiosMailACK" 
      #confirmation output  
      printMsg = "-acknowledged the Notification of " + @subjectTokens[4] + " about " 
      printMsg = printMsg + hostNfo  + "\n"
      printMsg = 'echo "' + printMsg + '" >> /var/log/nagAck.log'
      system(printMsg)
    elsif  subject.index("Service") != nil 
      #in above kind of SUBJECT Line, default HOST/SERVICE info is 8th Word, so
      hostNfo=@subjectTokens[7].split(/\//)[0]
      svcNfo=@subjectTokens[7].split(/\//)[1]  
      #preparing service acknowledgement string
      @ackCmd = "ACKNOWLEDGE_SVC_PROBLEM;"+hostNfo+";"+svcNfo 
      @ackCmd=@ackCmd+ ";1;1;1;urNagiosMailID@gmail.com;acknowledged through nagiosMailACK"
      #confirmation output
      printMsg = "-acknowledged the Notification of " + @subjectTokens[4] + " in " + svcNfo 
      printMsg = printMsg +  " @host: " + hostNfo + "\n"
      printMsg = 'echo "' + printMsg + '" >> /var/log/nagAck.log'
      system(printMsg)
    end

	now= Time.now.strftime("%s")
	runCmd="echo '[%lu] " + @ackCmd + "' " + now + " > " + @commandFile
#puts runCmd 
	result = %x[#{runCmd}]
	system('echo ' + result + '>> /var/log/nagAck.log')
#puts "over"
    system('echo>> /var/log/nagAck.log')
    system('echo>> /var/log/nagAck.log')
    return true
end    
###############################################
=begin
Example MAIL-SUBJECT for Host Level ACK
  NAG-SERVER-ID ack Fwd: ** PROBLEM Host Alert: HOST-NAME is DOWN **
Example MAIL-SUBJECT for Service Level ACK
  NAG-SERVER-ID ack Fwd: ** PROBLEM Service Alert: HOST-NAME/SERVICE-NAME is CRITICAL **
=end





#####################################################################
################################MAIN-PART##############################

#puts "Prefix all acknowledgement mails with '" + nagID + " ack ' with both spaces"
#puts "Eg: '"+nagID+" ack Fwd: ** PROBLEM Host Alert testBox is DOWN **'"

## starting infinite loop
loop do

$imap = Net::IMAP.new( CONFIG[:host], CONFIG[:port], CONFIG[:ssl] )
$imap.login( CONFIG[:username], CONFIG[:password] )
printMsg = 'echo "***************logged in " + CONFIG[:username] + "******************" >> /var/log/nagAck.log'
system(printMsg)

# select the INBOX as the mailbox to work on
$imap.select('INBOX')

messages_to_archive = []
@mailbox = "-1"

# retrieve all messages in the INBOX that
# are not marked as DELETED (archived in Gmail-speak)
$imap.search(["NOT", "DELETED"]).each do |message_id|
  # the mailbox the message was sent to
  # addresses take the form of {mailbox}@{host}
  @mailbox = $imap.fetch(message_id, 'ENVELOPE')[0].attr['ENVELOPE'].to[0].mailbox

  # give us a prettier mailbox name -
  # this is the label we'll apply to the message
  @mailbox = @mailbox.gsub(/([_\-\.])+/, ' ').downcase
  @mailbox.gsub!(/\b([a-z])/) { $1.capitalize }  
  
  envelope = $imap.fetch(message_id, "ENVELOPE")[0].attr["ENVELOPE"]
  #if envelope.from[0].mailbox==="abhishek" 
    system("echo 'ackFrom: #{envelope.from[0].mailbox}' >> /var/log/nagAck.log")
    system("echo 'Subject: #{envelope.subject}' >> /var/log/nagAck.log")
    if nagiosACK(envelope.subject,nagID)
      messages_to_archive << message_id
      begin
         #create the mailbox, unless it already exists
         $imap.create(@mailbox) unless $imap.list('', @mailbox)
         rescue Net::IMAP::NoResponseError => error
      end
      #copy the message to the proper mailbox/label
      $imap.copy(message_id, @mailbox)
    end
    system('echo "nagiosACK executed\n=----------=\n" >> /var/log/nagAck.log')
  #end
  #messages_to_archive << message_id
end

# archive the original messages
$imap.store(messages_to_archive, "+FLAGS", [:Deleted]) unless messages_to_archive.empty?

$imap.logout
system('echo "**************************logged out*****************************" >> /var/log/nagAck.log')
#exit(0)
sleep(900) #15min [time_in_sec]
##ending external loop
end
#######################################################################
##############################END-SCRIPT###############################
