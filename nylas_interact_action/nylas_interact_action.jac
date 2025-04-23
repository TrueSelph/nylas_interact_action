import:py json;
import:py logging;
import:py traceback;
import:py time;
import:py from logging {Logger}
import:py from jivas.agent.modules.agentlib.utils {Utils}
import:jac from jivas.agent.action.interact_action { InteractAction }
import:jac from jivas.agent.action.interact_graph_walker { interact_graph_walker }


node NylasInteractAction :InteractAction: {
    # finds availabilies and schedules appointments on calendars

    # set up logger
    static has logger:Logger = logging.getLogger(__name__);

    has strict:bool = False; # if strict, only actions belonging to matched functions will be executed.
    has intent_prompt:str = "You are an intent classification model for determining what users want to do with their appointments. Perform the following steps to determine the intent of MESSAGE with context from HISTORY. Do not provide explanations, only the final output:\n1. For each key-value mapping in ANCHOR_INDEX, examine the list of statements in value mapped to each key against the MESSAGE.\n2. Determine which list of statements best align with the intent of MESSAGE.\n3. If there are one or more confident alignments, return the corresponding key or keys in a comma-separated list, otherwise, return 'unclassified'. \n\nMESSAGE: \n{utterance}\n\nANCHOR_INDEX: \n{anchor_index}\n\nHISTORY: \n{history}";
    has prompt:str = "Refer to the APPOINTMENT_DETAILS below to perform entity extraction of the best answer from the user message. Do not make up answers. The best answer should sensibly satisfy 'prompt' key under each main key in the APPOINTMENT_DETAILS structure. Users may give one word answers in response to questions so use the HISTORY to determine what is being asked and extract the answer. \n Reference the the current date and time, {current_date}, to determine date and time the user is specifying. If a valid answer is extracted from the user message, return only a JSON structure using the key from the APPOINTMENT_DETAILS structure below and the matching extracted answer from the user message as the value.\n If there is no valid extracted answer for a key, return an empty json struct. Return extracted data without markdown delimiters, JSON or explanations!\n APPOINTMENT_DETAILS: {appointment_details}\nHISTORY:{history}";
    has model_name:str = "gpt-4o";
    has history:bool = True;
    has history_size:int = 5;
    has model_max_tokens:int = 4096;
    has max_statement_length:int = 500;
    has nylas_model_action:str = "NylasCalendarAction";
    has model_action:str = "LangChainModelAction";
    has model_op:str = "chatopenai";
    has temperature:float = 0.2;
    has exceptions:list = ['FunctionInteractAction']; # list of actions which are included in intent, regardless
    has timezone:str = "America/Guyana";
    has nylas_version:str = "v3";
    has nylas_base_url:str = "";
    has grant_id:str = "";
    has nylas_api_key:str= "";
    has cal_email:str = "";
    has calendar_id:str = "5df1d2dd7bb48a398b19bc44a2bbd18b1e10949f86e209e9a04d17f74fda88fd@group.calendar.google.com";
    has appointments:list = [];
    has anchors:list = ["Appointment", "Booking", "Cancelling", "Rescheduling", "Schedule", "Details and information necessary to make a booking", "book for time", "mentioning services, emails, dates and times to book for", "scheduling", "reserving", "agreeing to dates and times", "time is good", "The user shares personal information such as name and email"];
    has purpose_prompt: str = "Ask the user for the reason they would like to book the appointment. Tell them they can choose from the list of {options}. Use natural language. Do not ask for anything else other than their reason";
    has get_user_name_directive:str = "Ask the user to give their name to make the booking under";
    has get_email_prompt:str = "Ask the user to give their email so that you can search for their scheduled apointments. Remind them to ensure that the correct email format is used and that they enter the same email they used to book the appointment";
    has available_prompt:str = "Your goal is to inform the user that based on their request, the nearest available time they can select to book their appointment is at {times} but there are other times available. Represent time using the HH:MM am/pm format. \nAvoid giving more than 3 different times. Only use dates and times that are in available_times. DO not make up available times. \nGroup times that fall under the same date and show in the markdown list.";
    has change_acknowledge_prompt:str = "Tell the user that you will implement the change.Ask for more details if the request for change was not clear.";
    has time_unavailable_prompt:str = "Your goal is to let the user know that {date} at {time} is not available. Give them some currently available options. Be conversational and only give 3 other options currently available from {available}. Only use dates and times that are in 'available' list. Group times that fall under the same date. inform them that there are other times available too and they only need to ask and you will be able to tell them if it is available";
    has approve_appointment_prompt:str = "Your goal is to tell the details of their appointment are service - {purpose}, date -  {target_date}, time - {target_time}, cost - ${cost} duration - {duration} minutes. Represent the preceding information as a bullet list. The appointment is for {user_name} at email {email}. Use commas to seperate currency values and represent time in HH:MM am/pm format. Ask them to read over the details to confirm that this information is correct. Ask if they would they like to schedule the booking now if everything looks alright";
    has cancel_scheduling_prompt:str = "Your goal is to inform the user that the appointment booking has been cancelled but that you can assist them if they would need to schedule another appointment.";
    has appointment_booked_prompt:str = "Your goal is to tell the user their appointment has been booked. Also warn them that arriving 15 minutes after the appointment time or later may lead to the forfeit of their appointment. Ask if they need help with anything else. Use commas to seperate currency values";
    has approve_cancellation_prompt:str = "Ask the user if they are sure they would like to cancel or reschedule {purpose} appointment set on {date} at {time}. Represent time in HH:MM am/pm format. Do not give duplicate info";
    has get_appt_cancel_prompt:str = "Ask the user if they would like to cancel or reschedule {purpose} appointment set on {date} at {time}. List all appointments separately and ask them to please specify the date and time of the appointment they want to cancel. Represent time in HH:MM am/pm format. Do not give duplicate info";
    has appointment_deleted_prompt:str = "Tell the user that the appointment has been successfully cancelled";
    has give_info_prompt:str = "Answer the user by giving the necessary details from {appointment_details}";

    has intents:dict={
        "book_appointment":[
            "wanting to book appointment",
            "asking or giving information to book appointment",
            "finding available times to schedule appointments",
            "providing personal details such as name and email to book appointment"
        ],
        "cancel_appointment":[
            "wants to cancel appointment",
            "does not want to go to appointment anymore"
        ]
    };
    has services:dict={
        "exam":{
            "cost": 2000,
            "duration": 60
        },
        "check_up":{
            "cost": 1000,
            "duration": 30
        }
    };
    has appointment_details:dict = {}; 

    has functions:list = [
        {
            "type": "function",
            "function": {
                "name": "extract_user_details",
                "description": "Extracted information about user's personal details, appointment details, request for a specific service or scheduling preferences. Use the current date <datetime> to determine the date or time the user is referring to. Extract any information concerning the user wanting to bring in a machine or vehicle.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "user_name": {
                            "type": "string",
                            "description": "Returns the user's full name."
                        },
                        "email": {
                            "type": "string",
                            "description": "The user's email address. Extract any email the user gives in the format someone@domain.com" 
                        },
                        "purpose": {
                            "type": "string",
                            "enum": [
                                "exam",
                                "check_up",
                            ],
                            "description": "The type of appointment the user wants to book."
                        },
                        "date": {
                            "type": "string",
                            "description": "Returns the reference to a date that the user wants to make an appointment on. Extract in YYYY-MM-DD format."
                        },
                        "start_time": {
                            "type": "string",
                            "description": "the time given by the user. Only return time in HH:MM:SS format. Do whatever conversion is necessary. Never return words. Do not extract terms such as 'morning' or 'afternoon' or 'anytime' as times. Only return times in the 8:00 to 16:30 time range"
                        },
                        "intent": {
                            "type": "string",
                            "enum": [
                                "book_appointment",
                                "cancel_appointment",
                                "get_info"
                            ],
                            "description": "Utilize history to determine what is the user wants to do. Returns 'book_appointment' if the user wants to schedule an appointment and returns 'cancel_appointment' if the user indicates that they want to cancel previously set appointments. Return 'get_info' if user is asking for information about their previously set appointments. Affirmations or denials will alwys returneither book_appointment or cancel_appointment" 
                        } 
                    },
                    # "required": ["intent"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "extract_confirmation_choice",
                "description": "Determine if the user confirms that the provided details are accurate and want to proceed. It handles all forms of affirmatives (e.g., 'yes', 'post it', 'ox', 'sure') and negatives (e.g., 'no', 'cancel', 'nevermind', 'nah').",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "confirmation_choice": {
                            "type": "string",
                            "enum": [
                                "yes",
                                "change",
                                "no"
                            ],
                            "description": "Returns 'yes' if the user responds in the affirmative (e.g., 'yes,' 'that's right', 'sure', 'ok'). 'change' in cases where they indicate they want to make some change. 'no' for all cases indicating they wish to cancel the report (e.g., 'no,' 'cancel,' 'nah', 'nevermind')."
                        }
                    },
                    "required": [
                        "confirmation_choice"
                    ]
                }
            }
        }
    ];

    can touch(visitor: interact_graph_walker) -> bool {
        # authorize the interact to run
        if ("unclassified" in (visitor.interaction_node.get_intents())) {
            return False;
        }
        else{
            return True; 
        }

    }

    can execute(visitor: interact_graph_walker) -> dict {
        details_update_session = self.get_details_update_session(visitor);

        if(report := self.get_extracted_details(visitor)) {
            
            intent =report.get('intent', '');
            user_name = report.get('user_name', '');
            email = report.get('email', '');
            date = report.get('date', '');
            time_of_day = report.get('time_of_day', '');
            start_time = report.get('start_time', '');
            purpose = report.get('purpose', '');
            

            if(intent){
                details_update_session.set_intent(intent);
            }
            if(user_name){
                details_update_session.set_user_name(user_name);
            }
            if(email){
                details_update_session.set_email(email);
            }
            if(date){
                details_update_session.set_date(date);
            }
            if(time_of_day){
                details_update_session.set_time_of_day(time_of_day);
            }
            if(start_time){
                details_update_session.set_start_time(start_time);
            }
            if(purpose){
                details_update_session.set_purpose(purpose);
            }

            # save the session data to the visitor frame node for later use
            visitor.frame_node.variable_set(key=f"{self.get_type()}_session", value=details_update_session.export() );
        }
        intent = details_update_session.get_intent();
        user_name = details_update_session.get_user_name();
        email = details_update_session.get_email();
        target_date = details_update_session.get_date();
        time_of_day = details_update_session.get_time_of_day();
        target_time = details_update_session.get_start_time();
        purpose = details_update_session.get_purpose();
        event_id = details_update_session.get_event_id();
 
                
        base_version_url = self.nylas_base_url + "/" + self.nylas_version;
        grant_url = base_version_url + "/grants/" + self.grant_id;
        bearer_token = "Bearer " + self.nylas_api_key;

        end_time="";
        customer_status = "";
        calendar_id = self.calendar_id;
        current_date = Utils.date_now(timezone=self.timezone, date_format='%Y-%m-%d %H:%M:%S');
        
        services_list = [];
        for service in self.services{
            service_name = service.replace("_", " ");
            services_list.append(service_name);
        }
        services:dict = self.services.copy();

        if (self.history) {
            # grab the history
            prompt_messages = [];       
            statements = visitor.frame_node.get_transcript_statements(interactions = self.history_size, max_statement_length = self.max_statement_length);
            if (statements) {
                prompt_messages.extend(statements);
                self.logger.debug(f"history: {json.dumps(statements)}");
            }

            prompt_messages.extend([{"system": self.prompt}]);
            prompt_messages.extend([{"human": "{utterance}"}]);
        } else {
            # here we cater to whether we have context information or not..
            prompt_messages = [
                {"system": self.prompt},
                {"human": "{utterance}"}
            ];
        }     
        result_set = {};

        email = email.lower();

        prompt_variables = {};
        
        if(nylas_action := visitor.agent_node.get_actions().get(action_label=self.nylas_model_action)){

            if(intent == "book_appointment"){
                if(not purpose){
                    purpose_prompt_directive = self.purpose_prompt.format(options=services_list);
                    visitor.interaction_node.add_directive(directive=purpose_prompt_directive);
                }
                elif(purpose){
                    purpose.lower();
                    purpose = purpose.replace(" ", "_");

                    # finds the nearest available times if no date or time are provided
                    if(not target_date and not target_time){
                        start_time = nylas_action.round_up_time(current_date);
                    }

                    #sets a time to start searching availability 
                    elif(target_date and not target_time){
                        if(time_of_day == "morning"){
                            start_time = target_date + " 08:00:00";
                        }
                        elif(time_of_day == "midday"){
                            start_time = target_date + " 11:30:00";
                        }
                        elif(time_of_day == "afternoon"){
                            start_time = target_date + " 13:00:00";
                        }
                        else{
                            start_time = target_date + " 08:00:00";
                        }
                    }

                    elif(not target_date and target_time){
                        start_time = Utils.date_now() + " " + target_time;
                    }

                    elif(target_date and target_time){
                        start_time =target_date + " " + target_time;
                    }

                    if(purpose in self.services){
                        service_details = self.services[purpose];
                        if("cost" in service_details){
                            cost = service_details['cost'];
                        }
                        else{
                            cost = "";
                        }
                        if("duration" in service_details){
                            duration = service_details['duration'];
                        }
                        else{
                            duration = 30;
                        }
                    }

                    if(nylas_action.convert_to_epoch(start_time) < int(time.time())){
                        #ensures start time is in the future
                        epoch_time = nylas_action.convert_to_epoch(start_time);
                        current_epoch = int(time.time());
                        start_time = nylas_action.round_up_time(current_date);
                    }

                    times = nylas_action.get_available_times(start_time = start_time, base_url=base_version_url, duration= duration, cal_email=self.cal_email, calendar_id=calendar_id, bearer_token=bearer_token);
                
                    if(target_date and target_time){
                        if(start_time in times){
                            calendar_ids = [calendar_id];
                            if(not user_name){
                                visitor.interaction_node.add_directive(directive=self.get_user_name_directive);
                            }
                            elif(not email){
                                get_email_directive = "Ask the user to give their email so that you can schedule the booking on their calendar. Remind them to ensure that the correct email format is used";
                                visitor.interaction_node.add_directive(directive=get_email_directive);
                            }
                            if(email and user_name){
                                
                                if(choice := self.get_extracted_confirmation_choice(visitor)) {
                                    # if we do have all the necesssary information, and the confirmation is true, we send
                                    if(choice == 'yes') {
                                        for calendar_id in calendar_ids{
                                            event = nylas_action.create_event(
                                                bearer_token=bearer_token,
                                                grant_url=grant_url,
                                                calendar_id=calendar_id,
                                                start_time=start_time,
                                                duration=duration,
                                                purpose=purpose,
                                                email=email,
                                                user_name=user_name
                                                # customer_status= appt["customer_status"]
                                            );
                                            if('data' in event){
                                                visitor.interaction_node.add_directive(directive=self.appointment_booked_prompt);
                                                created_appt = {
                                                    "grant_url": grant_url,
                                                    "event_id": event['data']['id'],
                                                    "calendar_id": event['data']['calendar_id'],
                                                    "date": target_date,
                                                    "time": target_time,
                                                    "duration":duration,
                                                    "purpose":purpose,
                                                    "cost":cost,
                                                    "email":email,
                                                    "user_name":user_name
                                                };

                                                details_update_session.set_event_id(event_id=event['data']['id']);
                                                visitor.frame_node.variable_set(key=f"{self.get_type()}_session", value=details_update_session.export() );
                                                event_id = details_update_session.get_event_id();
                                                nylas_action.appointments.append(created_appt);
                                                visitor.frame_node.get_agent().export_descriptor();
                                            }else{
                                                error_prompt = "Tell the user that there was a problem scheduling the appointment and kindly ask them to try again";
                                                visitor.interaction_node.add_directive(directive=error_prompt);
                                            }
                                        }
                                    }elif(choice == 'no'){
                                        visitor.interaction_node.add_directive(directive=self.cancel_scheduling_prompt);
                                        # self.reset_session(visitor);
                                        details_update_session.set_purpose("");
                                        details_update_session.set_date("");
                                        details_update_session.set_start_time("");
                                        details_update_session.set_time_of_day("");
                                    }
                                    elif(choice == 'change'){
                                        visitor.interaction_node.add_directive(directive=self.change_acknowledge_prompt);
                                    }
                                }
                                else{
                                    approve_appointment_directive = self.approve_appointment_prompt.format(
                                        target_date=target_date,
                                        target_time=target_time,
                                        purpose=purpose,
                                        cost=cost,
                                        duration=duration,
                                        user_name=user_name,
                                        email=email
                                    );
                                    visitor.interaction_node.add_directive(directive=approve_appointment_directive);
                                }
                                visitor.frame_node.variable_set(key=f"{self.get_type()}_session", value=details_update_session.export() );
                                #books appointment once it is determined that the time requested is available
                            }
                        }
                        else{
                            details_update_session.set_start_time("");
                            time_unavailable_directive = self.time_unavailable_prompt.format(date= target_date,time=target_time, available=times);
                            visitor.interaction_node.add_directive(directive=time_unavailable_directive);
                        }
                    }
                    elif(times){
                        date_time = times[0].split(" ");
                        date = date_time[0];
                        details_update_session.set_date(date);

                        available_prompt_directive = self.available_prompt.format(times=times);
                        visitor.interaction_node.add_directive(directive=available_prompt_directive);
                    }
                    elif(not times){
                        no_times_prompt = "Your goal is to inform the user that there are no available times for the date they requested. Ask them if they would like to try another date or time. Be conversational and offer to help them find a time that works for them";
                        visitor.interaction_node.add_directive(directive=no_times_prompt);
                    }
                }
            }

            if(intent in ["cancel_appointment", "get_info"]){
                all_appointments = [];
                
                if(not event_id){
                    for appointment in nylas_action.appointments{
                        if(email){
                            if(appointment['email'] == email){
                                if(target_date and target_time){
                                    if(appointment['date']==target_date and appointment['time']==target_time){
                                        all_appointments.append(appointment);
                                        appt_details = appointment;
                                    }
                                }
                                elif(target_date){
                                    if(appointment['date']==target_date){
                                        all_appointments.append(appointment);
                                        appt_details = appointment;
                                    }
                                }
                                elif(target_time){
                                    if(appointment['time']==target_time){
                                        all_appointments.append(appointment);
                                        appt_details = appointment;
                                    }
                                }
                                elif(not target_date and not target_time){
                                    all_appointments.append(appointment);
                                    appt_details = appointment;
                                }
                            }
                        }
                        else{
                            visitor.interaction_node.add_directive(directive=self.get_email_prompt);
                        }
                    }
                    if(all_appointments){
                        booked_appointments: dict[str, list[str]] = {"date":[], "time":[], "purpose":[]};
                        for appointment in all_appointments{
                            booked_appointments['date'].append(appointment['date']);
                            booked_appointments['time'].append(appointment['time']);
                            booked_appointments['purpose'].append(appointment['purpose']);
                        }
                        if(len(all_appointments)>1){
                            appt_cancel_prompt_directive = self.get_appt_cancel_prompt.format(
                                purpose=booked_appointments['purpose'],
                                date=booked_appointments['date'],
                                time=booked_appointments["time"]
                            );
                            visitor.interaction_node.add_directive(directive=appt_cancel_prompt_directive);
                        }
                        elif(len(all_appointments)==1){
                            purpose=booked_appointments['purpose'];
                            date=booked_appointments['date'];
                            start_time=booked_appointments["time"];
                            event_id = all_appointments[0]['event_id'];
                        }
                    }
                }
                if(event_id){
                    if(not purpose){
                        purpose = details_update_session.get_purpose();
                    }
                    if(not target_date){
                        target_date = details_update_session.get_date();
                    }
                    if(not target_time){
                        target_time = details_update_session.get_start_time();
                    }
                    if(purpose){    
                        if(purpose in services.keys()){
                            service_details = self.services[purpose];
                            cost = service_details["cost"];
                            duration = service_details["duration"];
                        }

                        if(intent == "get_info"){
                            give_info_directive = self.give_info_prompt.format(
                                appointment_details={
                                    "purpose": purpose,
                                    "date": target_date,
                                    "time": target_time,
                                    "cost": cost,
                                    "duration": duration
                                }
                            );
                            visitor.interaction_node.add_directive(directive=give_info_directive);
                        }
                    }
                    choice = "";
                    if(choice := self.get_extracted_confirmation_choice(visitor)) {
                        # if we do have all the necesssary information, and the confirmation is true, we create the event on the calendar
                        if(choice == 'yes') {
                            deleted_event = nylas_action.delete_event(
                                grant_url=grant_url,
                                calendar_id=calendar_id,
                                event_id=event_id,
                                bearer_token=bearer_token
                            );
                            if(deleted_event){
                                for appointment in nylas_action.appointments{
                                    if(event_id == appointment['event_id']){
                                        nylas_action.appointments.remove(appointment);
                                    }
                                }
                                visitor.interaction_node.add_directive(directive=self.appointment_deleted_prompt);
                                details_update_session.set_event_id(event_id="");
                                details_update_session.set_date("");
                                details_update_session.set_start_time("");
                                details_update_session.set_purpose("");
                                details_update_session.set_time_of_day("");
                            }
                        }
                    }
                    elif(not choice and (intent == "cancel_appointment")){
                        # if we do not have a confirmation choice, we ask the user to confirm cancellation              
                        approve_cancellation_prompt_directive = self.approve_cancellation_prompt.format(
                            purpose=purpose,
                            date=target_date,
                            time=target_time
                        );
                        visitor.interaction_node.add_directive(directive=approve_cancellation_prompt_directive);
                    }
                }
                
            }
            visitor.frame_node.variable_set(key=f"{self.get_type()}_session", value=details_update_session.export() );
        }
        return visitor.export();
    }


    can healthcheck() -> bool {
        try {
            # Check core attributes that must exist and be correctly typed
            if (
                self.intent_prompt and
                self.prompt and
                self.model_name and
                self.model_max_tokens > 0 and
                self.max_statement_length > 0 and
                self.nylas_model_action and
                self.model_action and
                self.model_op and
                self.timezone and
                self.nylas_version and
                self.nylas_base_url and
                self.nylas_api_key and
                self.calendar_id and
                self.services and 
                self.appointment_details
            ) {
                return True;  # All checks passed
            }

            return False;  # One of the type checks or presence checks failed
        } except Exception as e {
            self.logger.error(f"An exception occurred in {self.label}:\n{traceback.format_exc()}\n");
            return False;
        }
    }
    can get_details_update_session(visitor: interact_graph_walker) -> DetailsUpdateSession {
        # check the user session for DetailsUpdateSession obj
        if( details_update_session_data := visitor.frame_node.variable_get(key=f"{self.get_type()}_session") ) {

            # wrap the session data in the object for easier handling
            details_update_session = DetailsUpdateSession(
                date=details_update_session_data.get('date', ''),
                time_of_day=details_update_session_data.get('time_of_day', ''),
                start_time=details_update_session_data.get('start_time', ''),
                user_name=details_update_session_data.get('user_name', ''),
                email=details_update_session_data.get('email', ''),
                purpose=details_update_session_data.get('purpose', ''),
                intent=details_update_session_data.get('intent', ''),
                event_id=details_update_session_data.get('event_id', ''),
            );

        } else {
            # this is an inital interaction, create a new session
            details_update_session = DetailsUpdateSession();
        }
        return details_update_session;
    }
    can get_extracted_details(visitor: interact_graph_walker) -> dict {
        # returns associated report description texts, if any

        # assess the response, look for any trace of applicable report descriptions
        results = visitor.interaction_node.get_functions(action_label = self.get_type());
        details = {};

        for item in results {
            name = item.get('name', '');
            name = item.get('name', '');
            date = item.get('args', {}).get('date', None);
            time_of_day = item.get('args', {}).get('time_of_day', None);
            user_name = item.get('args', {}).get('user_name', None);
            start_time = item.get('args', {}).get('start_time', None);
            email = item.get('args', {}).get('email', None);
            purpose = item.get('args', {}).get('purpose', None);
            intent = item.get('args', {}).get('intent', None);

            if ((name == 'extract_user_details')) {
                details = {
                    'date': date,
                    'time_of_day': time_of_day,
                    'start_time': start_time,
                    'user_name': user_name,
                    'email': email,
                    'purpose': purpose,
                    'intent': intent
                };
            }
        }
        return details;
    }

    can get_extracted_confirmation_choice(visitor: interact_graph_walker) -> str {
        # assess the response, look for any trace of applicable confirmation replies
        results = visitor.interaction_node.get_functions(action_label = self.get_type());

        for item in results {
            name = item.get('name', '');
            choice = item.get('args', {}).get('confirmation_choice', None);

            if ((name == 'extract_confirmation_choice') and choice) {
                return choice;
            }
        }

        return None;
    }
}
obj DetailsUpdateSession {
    # object which represents the report update session data

    has date:str = "";
    has time_of_day:str = "";
    has start_time:str = "";
    has purpose:str = "";
    has user_name:str = "";
    has email:str = "";
    has intent:str = "";
    has event_id:str = "";


    can set_user_name(user_name:str) {
        self.user_name = user_name;
    }

    can set_email(email:str) {
        self.email = email;
    }

    can set_date(date:str) {
        self.date = date;
    }

    can set_time_of_day(time_of_day:str) {
        self.time_of_day = time_of_day;
    }

    can set_start_time(start_time:str) {
        self.start_time = start_time;
    }

    can set_purpose(purpose:str) {
        self.purpose = purpose;
    }

    can set_intent(intent:str) {
        self.intent = intent;
    }

    can set_event_id(event_id:str) {
        self.event_id = event_id;
    }

    can get_user_name() {
        return self.user_name;
    }

    can get_email() {
        return self.email;
    }

    can get_date() {
        return self.date;
    }

    can get_time_of_day() {
        return self.time_of_day;
    }

    can get_start_time() {
        return self.start_time;
    }

    can get_purpose() {
        return self.purpose;
    }

    can get_intent(){
        return self.intent;
    }

    can get_event_id() {
        return self.event_id;
    }

    can export() {
        return {
            'user_name': self.user_name,
            'email': self.email,
            'date': self.date,
            'time_of_day': self.time_of_day,
            'start_time': self.start_time,
            'purpose': self.purpose,
            'intent': self.intent,
            'event_id': self.event_id
        };
    }
}