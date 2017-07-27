% plot distribution of peak delay times
close all
clear

% short-hand for indexing coordinates
x =     1;
y =     2;
z =     3;

alphaValues = 2.^(2:0.5:7);
betaValues = 2.^(0:0.5:7);
numRepeats = 10;
T = 1000;
burnIn = 500;
N = 100;
L = 2;
r0 = 1;
numAlphas = length(alphaValues);
numBetas = length(betaValues);

binWidth = 3;
maxLag = 20;
lagValues = -27:27; % should allow for an integer numbe of bins
% use two more bins than wanted (one for nicer plotting, one to discard edges)
nLagValues = length(lagValues);
minCorr = 0.5;
minOrder = 0.1; % as computing correlations for all pairs and delays is expensive, only do for relatively ordered collectives

exportOptions = struct('Format','eps2',...
    'Color','rgb',...
    'Width',12,...
    'Resolution',300,...
    'FontMode','fixed',...
    'FontSize',10,...
    'LineWidth',2);

precision = 2;

%% load results
binCentres = (min(lagValues)+2*binWidth):binWidth:(max(lagValues)-2*binWidth);
histPeakLag = NaN(numAlphas,numBetas,numRepeats,(nLagValues - 1)/binWidth - 1);
histPeakVar = NaN(numAlphas,numBetas,numRepeats);
for alphaCtr = 1:numAlphas
    alpha = alphaValues(alphaCtr);
    for betaCtr = 1:numBetas
        beta = betaValues(betaCtr);
        distributionFig = figure;
        distributionFig.Color='none';
        hold on
        plotCurrent = 0;
        order = NaN(numRepeats,1);
        for repCtr = 1:numRepeats
            % load results
            filename = ['results/' 'T' num2str(T,precision) '_N' num2str(N,precision)...
                '_L' num2str(L,precision) ...
                '_a' num2str(alpha,precision) '_b' num2str(beta,precision) ...
                '_run' num2str(repCtr) '.mat'];
            out = load(filename);
            % discard burn-in
            out.cells = out.cells(:,:,burnIn:end);
            order(repCtr) = mean(orderParameter(out.cells));
            if order(repCtr) >= minOrder
                dirCrossCorr = NaN(N*(N-1)/2,nLagValues);
                % only need to go over each pair once, since Cij(tau) = Cji(-tau)
                
                % calculate cross-correlations
                for lagCtr = 1:nLagValues % can be parfor-ed
                    lag = lagValues(lagCtr);
                    dirCrossCorr(:,lagCtr) = mean(directionalCrossCorrelation(out.cells,lag,r0),2);
                end
                
                % only keep cross-correlations if cells have been neighbours (within r0)
                pairDistances = NaN(N*(N-1)/2,T-burnIn);
                for timeCtr=1:T-burnIn % can be parfor-ed
                    pairDistances(:,timeCtr) = pdist(out.cells(:,1:3,timeCtr));
                end
                notNeighbours = min(pairDistances,[],2)>r0;
                dirCrossCorr(notNeighbours,:) = NaN;
                
                % find and plot peaks in crosscorr curves
                peakLags = NaN(N,N);
                peakCorrs = NaN(N,N);
                
                ij = 0;
                for jj = 1:(N-1)
                    for ii = (jj+1):N
                        ij = ij+1;
                        % if the two cells were never neighbours, their crossCorr = NaN
                        if any(~isnan(dirCrossCorr(ij,:)))
                            [pks, locs] = findpeaks(dirCrossCorr(ij,:),lagValues,...
                                'NPeaks',1,'SortStr','descend');
                            if ~isempty(pks), peakCorrs(ii,jj) = pks; end
                            if ~isempty(locs), peakLags(ii,jj) = locs; end
                            peakCorrs(jj,ii) = peakCorrs(ii,jj); % correlation is the same for the symmetric pair
                            peakLags(jj,ii) = -peakLags(ii,jj);% Cij(tau) = Cji(-tau)
                        end
                    end
                end
                
                % only plot lag times for corr>=minCorr - don't use
                % 'MinPeakHeight' parameter in findpeaks as it throws
                % warnings
                threshPeaks = peakCorrs>=minCorr;
                % discard peak lag times outside relevant range from
                % further calculation
                threshPeaks(abs(peakLags(threshPeaks))>maxLag) = false;
                if any(threshPeaks(:))
                    plotCurrent = 1;
                    %% save distribution
                    histPeakLag(alphaCtr,betaCtr,repCtr,:) = histcounts(peakLags(threshPeaks),...
                        'BinWidth',binWidth,'BinLimits',[min(lagValues)+binWidth/2 max(lagValues)-binWidth/2],...
                        'Normalization','probability');
                    histPeakVar(alphaCtr,betaCtr,repCtr) = var(peakLags(threshPeaks));
                end
            end
        end
        if plotCurrent
            boundedline(binCentres,...
                squeeze(nanmean(histPeakLag(alphaCtr,betaCtr,:,2:end-1),3)),...
                squeeze(nanstd(histPeakLag(alphaCtr,betaCtr,:,2:end-1),0,3)),'.-');
            ylim([0 max(max(histPeakLag(alphaCtr,betaCtr,:,:)))])
            xlim([-maxLag maxLag])
            % format figure
            ax = gca;
            ax.Box = 'off';
            ax.XLabel.String = '\tau_C';
            ax.YLabel.String = 'P';
            ax.Title.String = ['\alpha = ' num2str(alpha,3) ', \beta = ' num2str(beta,3),...
                ', \langle\Phi\rangle = ' num2str(nanmean(order),2)];
            ax.Title.FontWeight = 'normal';
            %% export figure
            filename = ['manuscript/figures/diagnostics/delayDist_T' num2str(T) '_N' num2str(N) ...
                '_L' num2str(L) '_a' num2str(alpha,precision) ...
                '_b' num2str(beta,precision)];
            set(distributionFig,'PaperUnits','centimeters')
            exportfig(distributionFig,[filename '.eps'],exportOptions);
            system(['epstopdf ' filename '.eps']);
            system(['rm ' filename '.eps']);
        end
        close(distributionFig)
    end
end
%% plot multi-line diagram of variance
exportOptions.FontSize = 14;
exportOptions.Width = '15';
legendString = num2str(round(alphaValues(1:2:end))');

sigmaFig = figure;
boundedline(betaValues,nanmean(sqrt(histPeakVar(1:2:end,:,:)),3),...
    permute(nanstd(sqrt(histPeakVar(1:2:end,:,:)),0,3)./...
    sqrt(sum(~isnan(histPeakVar(1:2:end,:,:)),3)),[3 2 1]),'alpha','.-','nan','gap')
ax1 = gca;
ax1.XScale = 'log';
ax1.XLabel.String = 'attraction-repulsion strength \beta'; ax1.YLabel.String = 'heterogeneity \sigma(\tau_C)';
sigmaFig.Color='none'; ax1.Box = 'on';
xlim([1 max(betaValues)])
ylim([0 1+ceil(max(max(max(sqrt(histPeakVar(1:2:end,:,:))))))])
% make an inset of non-log scale
inset = axes('position',...
    [0.33 0.59 0.4 0.335]);
boundedline(betaValues,nanmean(sqrt(histPeakVar(1:2:end,:,:)),3),...
    permute(nanstd(sqrt(histPeakVar(1:2:end,:,:)),0,3)./...
    sqrt(sum(~isnan(histPeakVar(1:2:end,:,:)),3)),[3 2 1]),'alpha','.-','nan','gap')
inset.XLim = [1 max(betaValues)];
inset.YLim = [4 12.5];
inset.YTick = [4 8 12];
inset.Box = 'on';
% save figure
filename = ['manuscript/figures/varianceDelayDiagram_T' num2str(T) '_N' num2str(N) ...
    '_L' num2str(L)];
set(sigmaFig,'PaperUnits','centimeters')
exportfig(sigmaFig,[filename '.eps'],exportOptions);
system(['epstopdf ' filename '.eps']);
system(['rm ' filename '.eps']);

%%
save('delayCorrResults.mat','alphaValues','betaValues','histPeakVar')