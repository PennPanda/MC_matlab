%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%disp('Plotting scheduling events')
fileID = fopen(strcat(testDir,'schedule.txt'));
C = textscan(fileID,'%*s %u64 %*s %s %*s %*s %*s %*s %s %*s %*s %s %*s %*s %s %*s %*s %s %*s');
fclose(fileID);
time = C{1};
deadline_ = C{4};
%deadline_start = hex2dec(deadline_{1}(3:end-1));

start = time(1);
%delta = C{2};
vcpu_ = C{3};
budget_ = C{5};
mode = C{6};
S = sprintf('%s ', mode{:});
mode = sscanf(S, '%d');

old_mode = 0; %assuming only the transition is traced
new_mode = 0;

% nr_vcpu = 0;
deadline = zeros(length(vcpu_),1);
budget = zeros(length(vcpu_),1);
vcpu=0;
for i = 1:length(vcpu_)  
    s2 = vcpu_{i};
    
    deadline_{i} = deadline_{i}(3:end-1); 
    d =  hex2dec(sprintf('%s', deadline_{i}));
    deadline(i) = d;
    
    budget_{i} = budget_{i}(3:end-1); 
    d =  hex2dec(sprintf('%s', budget_{i}));
    budget(i) = d;
    
    vcpu_{i} =s2(end-2:end-1);
    v = hex2dec(sprintf('%s', vcpu_{i}));
    vcpu(i) = v;
end

deadline_start = deadline(1);
time_diff=deadline_start-ms(1);
ms = ticks_to_ms(time);
 %assume one transition only
for i = 1:nr_vcpu
    mt = mode(vcpu == i-1);
    if length(mt) ~= 0
        new_mode(i) = max(mt);
        old_mode(i) = min(mt);
    end
end

idle_vcpu_id = 64;



for i = 1:(length(time) - 1)
   pos = [ms(i),-10.5, ms(i+1) - ms(i), 10];
   add_text = 1;
   color = getVcpuColor(vcpu(i),nr_vcpu);
   if color == [0 0 0]
           add_text = 0;
   end
   
   rectangle('Position',pos,'FaceColor',color);
   if add_text == 1 && vcpu(i) ~= idle_vcpu_id 
       label = strcat('v',int2str(vcpu(i)),' m',int2str(mode(i)),[char(10) 'd'],num2str(deadline(i)-deadline_start));
   	   h=text(ms(i),-5,label);
       set(h,'Clipping','on')
   end
end
title('circle-disable, diamand-enable, square-backlog, triangle-update, star-release')
xlabel('time in ms')



%read the mcr file, assuming there is only one mcr
fileID = fopen(strcat(testDir,'mcr.txt'));
C = textscan(fileID,'%*s %u64 %*s %*s %*s');
fclose(fileID);
mcr_time = C{1};
mcr = ticks_to_ms(mcr_time);


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%finding the endpoint of modechange
%three arrays representing two different types of endpoint
release_new = find_release_new(testDir,nr_vcpu,mcr);


finish_old = zeros(nr_vcpu,1);


%find the start of the last instance of the old job
%the last old job could be preempted!but the start is the last (partial) of
%the old job.
%dont do the calculation
last_old_index = zeros(nr_vcpu,1);
old_done = 0;
for i = 1:length(vcpu) 
    
    if vcpu(i) ~= idle_vcpu_id && strcmp(vcpu_type(vcpu(i)+1),'new') ~= 1
       
        if ( old_done == 0 && strcmp(vcpu_type(vcpu(i)+1),'old') == 1)%if old don't depend on mode
            %finish_old(vcpu(i)+1) = ms(length(ms));
            last_old_index(vcpu(i)+1) = find(vcpu==vcpu(i),1,'last');
            old_done = 1;
            %fprintf('vcpu %d is old done\n',vcpu(i));
            continue
        %for other types, this will find the last (partial) instance of the
        %old job
        elseif (finish_old(vcpu(i)+1) < ms(i) && mode(i) == old_mode(vcpu(i)+1))
            finish_old(vcpu(i)+1) = ms(i);
            last_old_index(vcpu(i)+1) = i;
            %fprintf('update finish old vcpu%d\n',vcpu(i));
        end
    end
end
%shift to the finish of the last old job
%The last old job is always at the end so no need to worry about preemption
for i = 1:nr_vcpu
    if ( strcmp(vcpu_type(i),'new') ~= 1) && last_old_index(i)~=0
        %fprintf('shifting vcpu%d\n',i-1);
        finish_old(i) = ms(last_old_index(i)+1);
    end
end

[all_finish_old_and_first_new,end_point3] = find_all_finish_old_and_first_new(nr_vcpu,vcpu,ms,deadline,finish_old,mode,new_mode,old_mode,mcr(1),vcpu_type);

%calculate job miss ratio
subtime=ms(ms>=mcr);
subbudget=budget(ms>=mcr);
subdeadline=deadline(ms>=mcr);
subtime=subtime(subtime<=end_point3);
subbudget=subbudget(subtime<=end_point3);
subdeadline=subdeadline(subtime<=end_point3);

end_point3_delay = end_point3-mcr(1);
label = 'endpoint3';
h=text(end_point3,-16.8,label);
set(h,'Clipping','on')

vcpu_endpoint3_latency = zeros(1,nr_vcpu);
for i = 1:nr_vcpu
    if (strcmp(vcpu_type(i),'old') == 1)
        vcpu_endpoint3_latency(i) = finish_old(i)- mcr(1);
    else
        vcpu_endpoint3_latency(i) = all_finish_old_and_first_new(i) - mcr(1);
    end
    if vcpu_endpoint3_latency(i) < 0
        vcpu_endpoint3_latency(i) = 0;
    end
    
   if all_finish_old_and_first_new(i) ~= 0 && strcmp(vcpu_type(i),'old') ~= 1 %for old vcpu dont print finnish new
       label = strcat('v',int2str(i-1),[char(10) 'f'],'in new');
       h=text(all_finish_old_and_first_new(i),-14.8,label);
       set(h,'Clipping','on')
       
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

hold on



%two arrays storing two different types of mcr duration calculated from
%previous arrays
mcr_latency_finish_old = zeros(nr_vcpu,1);
mcr_latency_release_new = zeros(nr_vcpu,1);


%actual loop that finds the diff and prints the texts
for i = 1:nr_vcpu
    
   if (release_new(i) ~= 0)
       label = strcat('v',int2str(i-1),[char(10) 'r'],'el new');
       h=text(release_new(i),-11.8,label);
       set(h,'Clipping','on')
       mcr_latency_release_new(i) = release_new(i) - mcr(1);
       disp(strcat('v',int2str(i-1),' mcr_release_new delay=',' ', num2str(mcr_latency_release_new(i)),'ms'));
   end
   label = strcat('v',int2str(i-1),[char(10) 'f'],'n old');
   h=text(finish_old(i),-13.6,label);
   set(h,'Clipping','on')
   
   mcr_latency_finish_old(i) = finish_old(i) - mcr(1);
   if ( mcr_latency_finish_old(i) >= 0)
    disp(strcat('v',int2str(i-1),' mcr_finish_old delay=',' ', num2str(mcr_latency_finish_old(i)),'ms'));
   end
end

